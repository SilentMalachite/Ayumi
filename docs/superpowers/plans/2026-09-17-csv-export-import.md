# CSV エクスポート / インポート 実装計画

## Context

職員が入力したデータを Excel で二次利用したい、また Excel で作ったデータを取り込みたい、という要望。
形式は CSV が最適(Excel で直接開ける・純 Elixir で完結・オフライン運用に合う)。週・月・年単位で出力できるようにする。
TODO.md L199 で「CSV 出力(月別実績)」は将来課題として列挙済み。インポートは新規。

### 合意済みの決定

| 項目 | 決定 |
|---|---|
| 形式 | UTF-8 **BOM 付き** CSV。取込は UTF-8(BOM 有無どちらも可)。Shift_JIS は拒否し「CSV UTF-8(コンマ区切り)で保存してください」と案内 |
| 依存 | `{:nimble_csv, "~> 1.2"}` を追加(純 Elixir・推移依存なし)。`NimbleCSV.RFC4180` を使用 |
| 出力対象 | 出欠実績(利用者×日付ごとに最新行を採用)/ 支援記録 / 目標進捗履歴 / 計画段階履歴 / 利用者台帳(期間なし) |
| 期間単位 | 週(月曜始まり)/ 月 / 年度(4/1〜3/31)/ 暦年。「単位 + 基準日」で、その日を含む期間を出力。利用者絞り込み可 |
| 日時 | CSV の日時列と期間境界は **JST**(固定 +9h、tzdata 不要)。既存画面の UTC 表示は今回触らない |
| 権限 | 出力 = 全職員 / 取込 = manager のみ |
| 取込対象 | ① 出欠実績 → ② 利用者台帳 → ③ 支援記録(最後に別途設計。今回は設計課題の記載のみ) |
| 取込方針 | append-only。全件成功 or 全件中止。プレビュー → 確認 → 1 トランザクションで確定。現在の最新行と同一内容の行は「変更なし」としてスキップ |

## 構成

```
lib/ayumi/jst.ex                       Ayumi.JST            today/1, format/1, utc_range/2(固定+9h を一箇所に集約)
lib/ayumi/csv.ex                       Ayumi.CSV            encode/2(BOM・数式エスケープ), decode/1(BOM除去・UTF-8検証・ヘッダ対応・行番号)
lib/ayumi/csv/cell.ex                  Ayumi.CSV.Cell       format_* / parse_* の純粋関数(日付・時刻・○/空・enum ラベル)
lib/ayumi/csv/attendance.ex            headers/0, dump/1, parse/1   ← 列定義 columns/0 を1リストで持ち出力と取込で共有(往復保証)
lib/ayumi/csv/{support_records,goal_progress,plan_phase_events,service_users}.ex
lib/ayumi/exports.ex                   Ayumi.Exports        change_request/1, period_label/1, build/2 → {:ok, %{filename, content}}
lib/ayumi/exports/{period,dataset,request}.ex   Period は純粋関数 / Request は embedded schema(パラメータ検証は changeset)
lib/ayumi/imports.ex                   Ayumi.Imports        preview_attendance/2, commit_attendance/2(manager 再チェック), max_bytes/0, max_rows/0
lib/ayumi/imports/preview.ex           %Preview{to_insert, unchanged, skipped, errors, warnings, ignored_headers, ...}
lib/ayumi_web/controllers/export_controller.ex   send_download(conn, {:binary, ...}) のみ(約10行)
lib/ayumi_web/live/export_live/index.ex          /exports(全職員)。phx-change で期間ラベルと download リンクを再計算
lib/ayumi_web/live/import_live/index.ex          /admin/import(manager)。allow_upload(:csv, accept: ~w(.csv), max_entries: 1)
```

`Ayumi.Plans` への追加(既存関数・既存テストは変更しない):
- `list_attendance_records_between(from, to, opts)` — id 昇順、退所者含む、`:service_user_id` 絞り込み
- `latest_attendance_by_user_date(rows)` — 純粋 fold。出力と取込差分で共用
- `list_support_records_between/3`, `list_goal_progress_between/3`, `list_plan_phase_events_between/3` — DateTime 範囲を受け取る(JST 変換は `Exports` 側のみ。`Plans` はタイムゾーン非依存のまま)
- enum モジュールに `from_label/1 :: {:ok, atom} | :error`(`ProvisionType` は Inc 4、`Gender`/`SupportCategory`/`EnrollmentStatus` は Inc 5)

ルーティング(`lib/ayumi_web/router.ex`):
- `live "/exports"` を `:require_authenticated_user` live_session に、`live "/admin/import"` を `:require_manager` live_session に追加
- `get "/exports/download", ExportController, :download` を L75 の既存コントローラルートの隣に追加(`:browser` は html のみ accept のため `.csv` 拡張子ルートにしない。LanOnly は endpoint plug なので自動適用)
- ナビ(`lib/ayumi_web/components/layouts.ex` L49-59)に「CSV出力」(全員)と「CSV取込」(manager のみ、L53-55 と同じ gate)を追加

再利用するもの: `BackupLive.Index` の画面パターン(result assigns + alert パネル)、`User.display_name/1`、enum の `label/1`、`Plans.create_attendance_record/2`・`create_service_user/1`・`change_attendance_record/2`、`core_components` の `<.button href download>`(既に許可済み)。

## CSV 列定義

共通: 日付 `YYYY-MM-DD` / 時刻 `HH:MM` / 真偽 `○` or 空 / enum は日本語ラベル / 日時は JST 秒まで / 記録者は `display_name`。

- **出欠実績**: `利用者ID, 氏名, 利用日, 曜, 提供形態, 開始, 終了, 送迎(往), 送迎(復), 備考, 記録者, 記録日時(日本時間), 記録ID`
  - 取込で読む列: `利用者ID, 氏名, 利用日, 提供形態, 開始, 終了, 送迎(往), 送迎(復), 備考`(全て必須ヘッダ。備考列が欠けた CSV で既存備考を消す訂正を防ぐ)。他は無視
- **支援記録**: `利用者ID, 氏名, 在籍状態, 区分, 内容, 記録者, 記録日時(日本時間), 記録ID`
- **目標進捗**: `利用者ID, 氏名, 在籍状態, 計画ID, 計画期間開始, 計画期間終了, 目標ID, 短期目標, 進捗, 所見, 記録者, 記録日時(日本時間), 記録ID`
- **計画段階**: 上記から `目標ID, 短期目標` を除き `進捗` → `段階`
- **利用者台帳**: `利用者ID` + フラット 23 項目(フォームのラベルを流用)+ `障害者手帳`(出力専用の要約列)

設計判断:
- **退所者は全エクスポートに含める**(`在籍状態` 列で判別)。画面の除外は UI 都合、CSV は監査資料のため黙って欠落させない
- **JST 境界は半開区間** `[from 00:00 JST, to+1日 00:00 JST)`
- **数式インジェクション対策**: `= + - @ TAB CR` で始まるセルに `'` を前置、decode で対称に除去(「- 特になし」のような所見が Excel で `#NAME?` になるのも防ぐ)
- **取込の寛容パース**(構造化セルのみ、NFKC + trim 後): 日付 `YYYY/M/D` も可、時刻 `H:MM` / `HH:MM:SS` も可、真 = `○ 〇 1 TRUE`、偽 = 空 `× 0 FALSE`。ヘッダも NFKC で照合(`送迎(往)` 全角括弧も一致)

## 取込パイプライン(出欠)

サイズ上限(2MB)→ `CSV.decode` → 行数上限(5,000 行)→ 利用者解決 → attrs 生成 → `Plans.change_attendance_record/2` で検証 → ファイル内重複チェック → 現在の最新状態と差分 → `%Preview{}`

- 利用者解決: `利用者ID` 優先。空なら `氏名` の完全一致(一意のときのみ)。両方あれば一致必須。曖昧・不在は行エラー
- 行番号は Excel の行番号(ヘッダ = 1 行目)。複数行セルがあってもずれないようレコード index 基準
- ファイル単位エラー(`{:error, msg}`): 非 UTF-8、パース失敗、必須ヘッダ欠落・重複、空、上限超過。行単位エラーは `errors` に集約(画面表示は 100 件で打ち切り「他 N 件」)
- 同一ファイル内の (利用者, 日付) 重複は行エラー(後勝ちにしない)
- プレビュー表示: 「追加 N 件(うち訂正 M 件)/ 変更なし / エラー」。訂正件数は想定外の上書きに気づく安全信号
- **確定時の再検証**: `commit_attendance/2` はトランザクション内で `preview.rows` から再計画し、確認済みプレビューと差があれば `{:error, :stale, fresh_preview}` を返して再確認を促す。各行は `Plans.create_attendance_record(scope, attrs)`、失敗は `Repo.rollback`
- 画面に明記: 「CSV から行を消しても記録は削除されません」(append-only)
- 利用者台帳取込(Inc 5): 新規作成のみ。**既存判定** = 受給者証番号一致(先頭ゼロ無視)/ 氏名+生年月日一致 / 既存の `利用者ID` のいずれか → 「既存」としてスキップ。存在しない `利用者ID` は行エラー。手帳(has_many)は v1 では取り込まない。空セルは attrs から省く(`enrollment_status` の既定値を潰さない)

## 増分(各回 TDD・`mix review` 通過・独立して出荷可能)

| Inc | 内容 | 先に書くテスト |
|---|---|---|
| **1** | nimble_csv 追加、`JST`、`Period`、`CSV.encode`、`Cell` フォーマッタ、出欠の範囲クエリ+fold、`CSV.Attendance`(dump)、`Exports`、`ExportController`、`ExportLive`、ルート、ナビ | `jst_test` / `exports/period_test`(日曜→月曜週、1〜3月→前年度、4/1・3/31 境界)/ `csv_test`(BOM・CRLF・引用・エスケープ)/ `plans_test` 追加 / `exports_test` / `export_controller_test`(未認証リダイレクト、supporter 200、`text/csv`、attachment、BOM)/ `export_live_test` |
| 1b(任意) | `AttendanceLive.Index` ヘッダ(L41-65)に当月「CSV出力」リンク | LiveView アサーション 1 件 |
| **2** | 支援記録・目標進捗・計画段階の `*_between` とデータセットモジュール | JST 境界(`2026-08-31T15:00:00Z` は 9 月、`14:59:59Z` は 8 月)、退所者を含む、既存 `list_support_records/2` テスト不変 |
| **3** | 利用者台帳エクスポート | ヘッダ = フォームラベル、手帳要約列 |
| **4a** | `from_label`、`Cell` パーサ、`CSV.decode`、`Attendance.parse`、`Imports`、`Preview` | **往復**: `Exports.build` → `preview_attendance` が全件「変更なし」/ 1 セル編集 → 訂正 1 件 / Excel 変形(`2026/9/1`, `9:00`, BOM なし, LF, 末尾 `,,,,`)/ Shift_JIS 拒否 / 重複 / stale / rollback / supporter 拒否 |
| **4b** | `ImportLive`、`:require_manager` ルート、ナビ | `file_input` + `render_upload` フロー、supporter は `{:error, {:redirect, %{to: "/"}}}` |
| **5** | 利用者台帳インポート | 新規のみ、既存スキップ、ファイル内重複、空セル省略 |
| **6a** | `support_records.support_date`(支援日)を追加(2026-09-17 合意)。既存行は `date(recorded_at, '+9 hours')` で初期化。未指定は記録日(JST)、未来日は不可。一覧・フィルタ・まとめ画面・CSV出力を支援日基準に | `support_record_test`(既定値・未来日・並び・フィルタ)、`log_range_queries_test`、`exports_test`、LiveView。マイグレーションの up/down は開発DBのコピーで確認 |
| **6b** | 支援記録インポート。読む列は `利用者ID, 氏名, 支援日, 区分, 内容`。自然キーがないため、利用者・支援日・区分・内容が既存と完全一致する行は「変更なし」、それ以外は新規(訂正の概念なし)。`記録ID` つきで内容が変わっている行は注意。退所者は現行ルールどおり行エラー | 往復(出力→取込で全件変更なし)、編集行は新規+注意、ファイル内重複、退所者エラー、LiveView |
| **6c** | 別件: 退所者の過去の支援記録を、取込に限って許可(2026-09-17 合意)。`create_support_record/3` の `allow_withdrawn: true` を取込だけが渡す。確認画面に注意を表示。画面入力の拒否は維持 | `support_record_test`(オプションは退所者ルールだけを外す)、`imports/support_records_test`、LiveView |

各 Inc で更新: `CHANGELOG.md`(### 追加)、`README.md`(### 運用ツール、Excel 取り扱い注意・個人情報の持ち出し注意)、`CLAUDE.md`(Optional (done))。Inc 1 で `TODO.md` L199 を消化、計画書を `docs/superpowers/plans/2026-09-17-csv-export-import.md` に保存。

## リスク・注意

- Excel は表示文字列で保存する: 日付を `9月1日` 表示にすると年が落ちて行エラー。電話・受給者証番号の先頭ゼロは Excel 内で消える → README に「列を文字列に設定」と記載、受給者証番号が 10 桁でない場合は警告(非ブロック)
- サイズ見積: 出欠 1 年 ≈ 8.6k 行 / 0.8MB、支援記録 1 年 ≈ 3.5MB。ストリーミング不要
- 取込 5,000 行上限は SQLite `busy_timeout: 5_000` 内に収めるため。月単位(全員 ≈ 1,100 行)の往復が想定用途。年単位の取込は月ごとに分割
- Windows ブラウザは `.csv` を `application/vnd.ms-excel` と申告する → `accept` は拡張子指定
- ファイル名は日本語(`send_download` が RFC 5987 でエンコード)
- Credo の複雑度チェック対策: セルパーサは小さな多節関数で書く

## 気づいた点(今回は対応しない・別途提案)

- 画面の日時が UTC 表示、`list_support_records/2` のフィルタも UTC 0 時基準
- 実績記録票の時刻が `HH:MM:SS` で印字される(`sheet.ex` L188)
- Ecto 既定の検証メッセージが英語のまま(`ja` ロケールなし)
- `fold_attendance_sheet` は新しい fold を再利用できる
- 取込行に「取込バッチ」の印がない(要スキーマ変更)

## 検証

1. 各 Inc: 新規テストパスで `mix test` → `mix review`
2. supporter で手動確認: `/exports` の期間ラベルが単位ごとに正しい / ダウンロード後もフォームが反応する(LiveView ソケット生存)/ `/admin/import` は `/` へリダイレクト
3. manager で往復確認: 1 か月分を出力 → Excel と Numbers で開く(BOM で日本語表示、`-` で始まる備考が無傷)→ 1 セル編集 → CSV UTF-8 で保存 → 取込プレビューが「訂正 1 件」→ 同じファイルを再取込で全件「変更なし」→ 通常の CSV(Shift_JIS)で保存したものは日本語メッセージで拒否
4. stale 確認: プレビュー後、別タブで入力画面から 1 行保存 → 確定すると stale になり新プレビューが表示される
