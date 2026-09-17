# 変更履歴

本ファイルの記法は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に準拠し、
バージョニングは [セマンティック バージョニング](https://semver.org/lang/ja/) に従います。

## [未リリース]

## [0.3.0] — 2026-09-17

Excel と CSV でデータをやり取りできるようになりました（全職員の CSV 出力、サービス管理責任者の
CSV 取込）。あわせて支援記録に「支援日」を追加し、画面の日時と「今日」の判定を日本時間に揃えました。

> **更新時の注意**: DB マイグレーションがあります（`support_records.support_date`）。ビルド済み
> リリースは起動スクリプトが `Ayumi.Release.migrate()` を実行します。ソースから動かしている場合は
> `mix ecto.migrate` を実行してください。

### 追加

- **CSV 出力（出欠・実績記録）**: 全職員が使える `/exports` 画面を追加。出力するデータ・
  期間の単位（週＝月曜始まり／月／年度＝4月〜翌3月／暦年）・基準日・利用者（任意）を選ぶと、
  基準日を含む期間の CSV をダウンロードできます。append-only ログを利用者×利用日ごとに
  畳み込み、最新行（訂正後の内容）だけを出力します。退所者の記録も含みます。
  - ファイルは Excel でそのまま開ける UTF-8（BOM 付き）・CRLF・RFC 4180 形式。`=` `+` `-` `@`
    などで始まるセルには `'` を前置し、Excel に数式として解釈されないようにしています。
  - 記録日時は日本時間（JST）で出力します（`Ayumi.JST`。固定 +9 時間でタイムゾーン DB 不要）。
  - **Exports コンテキスト**: `Ayumi.Exports.build/2`、期間計算の純粋関数
    `Ayumi.Exports.Period`、出力条件の changeset `Ayumi.Exports.Request`。CSV の符号化は
    `Ayumi.CSV`、列定義は `Ayumi.CSV.Attendance`。ダウンロードは
    `AyumiWeb.ExportController`（`GET /exports/download`）。
  - **Plans コンテキスト**: `list_attendance_records_between/3`（期間・全利用者）と
    純粋関数 `latest_attendance_by_user_date/1` を追加。
- **CSV 出力（支援記録／目標進捗の履歴／計画段階の履歴）**: `/exports` の「出力するデータ」に
  3 種類のログを追加。記録日時（`recorded_at`）で期間を絞り、古い順に出力します。
  - 期間の境界は日本時間の 0 時です（例: 9 月分は `2026-08-31T15:00:00Z` 以上
    `2026-09-30T15:00:00Z` 未満）。変換は `Ayumi.Exports` が `Ayumi.JST.utc_range/2` で行い、
    `Plans` はタイムゾーンに依存しません。
  - 退所者の記録も含め、`在籍状態` 列で判別できます。画面の支援記録一覧
    （`list_support_records/2`。退所者を除外・UTC 基準）の挙動は変えていません。
  - **Plans コンテキスト**: `list_support_records_between/3`、`list_goal_progress_between/3`、
    `list_plan_phase_events_between/3`（半開区間 `[from, to)`・`:service_user_id` 絞り込み）。
  - 列定義は `Ayumi.CSV.SupportRecords` / `Ayumi.CSV.GoalProgress` /
    `Ayumi.CSV.PlanPhaseEvents`。ヘッダ行とデータ行を 1 つの列リストから導く
    `Ayumi.CSV.Columns` を共有します。
- **CSV 出力（利用者台帳）**: `/exports` の「出力するデータ」に利用者台帳を追加。期間の指定は
  なく、退所者を含む全員の現在の登録内容を、登録フォームと同じ並び・同じ項目名で出力します
  （ファイル名は出力日付き: `利用者台帳_2026-09-17.csv`）。障害者手帳は 1 セルに要約します
  （例: `身体障害者手帳 第123号 下肢機能障害 3級 / 療育手帳 B2`）。
  - `Ayumi.Exports.Dataset.periodic?/1` で期間の要否を判定し、`Ayumi.Exports.Request` は
    期間つきのデータセットのときだけ単位と基準日を必須にします。画面も期間の入力欄を隠します。
  - **Plans コンテキスト**: `list_service_users/1` に `:preload` オプションを追加（既定は従来どおり）。
  - 列定義は `Ayumi.CSV.ServiceUsers`。
- **CSV 取込画面（出欠・実績記録）**: サービス管理責任者専用の `/admin/import`
  （`AyumiWeb.ImportLive.Index`、ナビに「CSV取込」）。CSV を選んで「内容を確認」を押すと、
  何も書き込まずに「追加 N 件（うち訂正 M 件）／変更なし／エラー」を表示し、エラーは行番号・
  列名つきの一覧（100 件まで）で示します。エラーがなければ「取込を実行」で確定します。確認の
  あとに他の職員が同じ日を記録していた場合は、内容を計算し直して再確認を求めます。
- **CSV 取込の土台（出欠・実績記録／コンテキスト層）**:
  `Ayumi.Imports.preview_attendance/2` がファイル全体を解析・検証して「何が書き込まれるか」を
  書き込まずに計画し（`Ayumi.Imports.Preview`: 追加／訂正／変更なし／エラー）、
  `commit_attendance/2` がトランザクション内で計画し直して、確認時と同じ内容のときだけ
  書き込みます（変わっていれば `{:error, :stale, 新しいプレビュー}`）。
  - append-only: 登録は `Plans.create_attendance_record/2` 経由。既存の利用日は訂正行の追加に
    なり、現在の最新行と同じ内容の行は「変更なし」としてスキップします（同じファイルを 2 回
    取り込んでもログは増えません）。CSV から行を消しても記録は削除されません。
  - 全件成功か全件中止。行エラーは Excel の行番号と列名つきで全件まとめて返します。同一ファイル内の
    同じ利用者・利用日の重複は後勝ちにせずエラーにします。
  - 利用者は `利用者ID` を優先し、空なら `氏名` の一意一致で特定。両方あれば一致が必須です
    （全角・半角や空白の違いは無視）。
  - `/exports` で出力した出欠 CSV はそのまま取り込めます（往復）。Excel が書き換えがちな
    `2026/9/1`・`9:00`・全角文字・BOM なし・LF・末尾の空列も受け付けます。Shift_JIS は拒否し、
    「CSV UTF-8（コンマ区切り）」での保存を案内します。上限は 2 MB・5,000 行。
  - サービス管理責任者のみ（コンテキストでも `Scope.manager?/1` を確認）。
  - `Ayumi.CSV.decode/1`、`Ayumi.CSV.Cell` の `parse_*`、`Ayumi.CSV.Columns.parse_row/2`
    （列定義に取込仕様を追加し、出力と取込で 1 つの列リストを共有）、
    `Ayumi.CSV.Attendance.parse/1`、`ProvisionType.from_label/1` を追加。
- **CSV 取込（利用者台帳）**: `/admin/import` の「取り込むデータ」で利用者台帳を選べます。
  **新規作成のみ**で、登録済みの利用者は変更せずスキップします（台帳の変更は、楽観ロックと
  手帳の行を持つ編集画面で行います）。
  - 登録済みの判定: `利用者ID` が存在する／`受給者証番号` が一致（Excel が落とす先頭の 0 は
    無視）／`氏名` と `生年月日` がともに一致（全角・半角や空白の違いは無視）。存在しない
    `利用者ID` はエラーです（新しい利用者は空欄にします）。
  - 同一ファイル内で同じ人（氏名＋生年月日、または受給者証番号）が重複していればエラー。
  - 取込はできるが確認してほしい行は「注意」として表示します: 受給者証番号が 10 桁でない、
    同じ氏名の利用者が登録済みだが生年月日で照合できない。
  - 空欄のセルは送らないので既定値が生きます（在籍状態の既定は「在籍」）。障害者手帳の列は
    取り込みません。`/exports` で出力した台帳を取り込むと全件「既存」になります（往復）。
  - `Ayumi.Imports.preview_service_users/2` / `commit_service_users/2`、データセットで振り分ける
    `Imports.preview/3` / `commit/2`、`Ayumi.Imports.Dataset`。計画ロジックを
    `Ayumi.Imports.AttendancePlan` / `Ayumi.Imports.ServiceUsersPlan` に分け、照合キーは
    `Ayumi.Imports.Matching`。`Preview` に `skipped` / `warnings` を追加。
  - `Gender` / `SupportCategory` / `EnrollmentStatus` に `from_label/1`、
    `Ayumi.CSV.ServiceUsers` に取込仕様（`parse/1` ほか）を追加。
- **CSV 取込（支援記録）**: `/admin/import` の「取り込むデータ」で支援記録を選べます。Excel に
  あった過去の記録を、支援日つきで取り込めます。
  - 読む列は `利用者ID`・`氏名`・`支援日`・`区分`・`内容`（支援日・区分・内容は必須）。`記録ID` の列は
    任意で、手作りのファイルには不要です。記録者は取り込んだ人、記録日時は取り込んだ時刻です。
  - 支援記録には自然キーがない（同じ人に同じ日の記録が複数あるのが普通）ため、「訂正」はありません。
    利用者・支援日・区分・内容がすべて同じ記録が既にある行は「変更なし」としてスキップし（再取込や、
    出力したファイルの取込ではログが増えません）、それ以外は新しい記録として追加します。出力した
    CSV の内容を書き換えて取り込むと、元の記録は残ったまま新しい記録が追加されます。`記録ID` から
    それが分かる行には「注意」を表示します。
  - 同一ファイル内の完全に同じ行はエラー。未来の支援日は行エラーです（書き込み時と同じ changeset
    `Plans.support_record_changeset/3` でプレビュー時に検証）。
  - **退所した利用者の過去の記録は、取込に限って登録できます**（在籍中に書かれた記録を移行するため）。
    確認画面に「注意」として表示します。画面からの入力は従来どおり拒否します。
    `Plans.create_support_record/3` / `support_record_changeset/3` の `allow_withdrawn: true` で、
    渡すのは CSV 取込（`Ayumi.Imports.SupportRecordsPlan.write_opts/0`）だけです。
  - `Ayumi.Imports.preview_support_records/2` / `commit_support_records/2`、
    `Ayumi.Imports.SupportRecordsPlan`。利用者の特定（ID 優先・氏名の一意一致）を
    `Ayumi.Imports.ServiceUserResolver` に切り出し、出欠の取込と共有（挙動は不変）。
    `Ayumi.CSV.Columns` に任意の見出し（`optional_header`）、`SupportRecordCategory.from_label/1`、
    `Plans.get_support_records/1` を追加。
- 依存に `nimble_csv`（純 Elixir・実行時のネットワーク不要）を追加。

### 変更

- **支援記録に「支援日」（`support_date`）を追加**: 支援した日と、記録した瞬間（`recorded_at`）を
  分けました。出欠の `service_date` と同じ考え方で、あとから入力した記録や CSV 取込でも
  「いつの支援か」を保持できます。
  - 既存の記録は、記録日時の日本時間の日付で埋めます（新しい導出列の初期化で、記録内容は
    書き換えません）。SQLite は既存列を NOT NULL にできないため、必須は changeset で保証します。
  - 入力フォームに「支援日」（既定は日本時間の今日）。未指定なら記録した日になり、**未来の日付は
    指定できません**（`SupportRecord.put_audit/3`。時計はコンテキストから渡すので changeset は
    純粋なまま）。
  - 一覧・フィルタ・利用者まとめ画面は支援日基準になりました（`list_support_records/2` の
    `:from` / `:to`、`list_recent_support_records/2` の並び）。フィルタの初期値も日本時間の今日に
    なり、朝 9 時前の記録が前日扱いになる問題はこの画面では解消しています。一覧には「支援日」と
    「記録日時」の両方を表示します。
  - CSV 出力の支援記録に `支援日` 列を追加し、期間は支援日で絞ります
    （`list_support_records_between/3` は日付の範囲を受け取る形に変更）。
- **画面の日時を日本時間で表示**: これまで UTC のまま（日本時間より 9 時間遅れて）表示していた
  日時を、日本時間に揃えました。対象は支援記録一覧と利用者まとめ画面の「記録日時」、支援計画画面の
  目標進捗・計画段階の履歴の時刻、DB バックアップの保存時刻（「（日本時間）」と明記）です。
  - 表示は共通コンポーネント `<.jst_datetime value={...} />`（`AyumiWeb.CoreComponents`）に集約し、
    変換は CSV と同じ `Ayumi.JST.format/2`（`:minute` / `:second`）を使います。`<time>` 要素の
    `datetime` 属性には元の UTC 時刻を残します。
  - 保存形式（UTC）は変わりません。支援計画画面の履歴は、これまで `2026-06-18 01:02:03Z` のような
    生の値を出していましたが、他の画面と同じ `YYYY-MM-DD HH:MM` 形式になります。

### 修正

- **「今日」を日本時間で判定**: ダッシュボードのモニタリング期限・受給者証期限、利用者まとめ画面の
  期限バッジ、出欠入力・実績記録票の初期表示月が、UTC の日付（`Date.utc_today/0`）で「今日」を
  決めていたため、日本時間の 0〜9 時は前日扱いになっていました（毎月 1 日の朝に出欠画面を開くと
  前月が表示される、期限切れの判定が 1 日遅れる、など）。すべて `Ayumi.JST.today/1` に揃えました。
  - `AttendanceLive.MonthParams.parse/2` は基準日を引数で受け取れるようにし（既定は日本時間の今日）、
    境界の日付で単体テストしています。`Plans.list_monitoring_deadline_alerts/3` と
    `list_certificate_expiry_alerts/3` の既定値も日本時間の今日です。
  - 時刻に依存する不具合は通常のテストでは再現しにくいため、`lib/` に `Date.utc_today()` が
    現れたら失敗するガードテストを `test/ayumi/jst_test.exs` に置きました。
- テストの間欠的な失敗（`Exqlite.Error: Database busy`）を解消。DB を使うのに `async: true` だった
  テストモジュール 6 つ（`plans_test.exs` と `plans/` 配下の 5 つ）を `async: false` にしました。
  SQLite は書き込みが同時に 1 つのため、並行するテストが書き込みロックを取り合い、待ちが busy
  timeout を超えると落ちていました（CI で発生）。`Ayumi.DataCase` の説明にもこのルールを明記。
- GitHub Release のリリースノートに変更内容が載らない不具合を修正（v0.2.0・v0.2.1 は空でした）。
  リリース用ワークフローが `## [未リリース]` の節を読んでいましたが、リリースコミットでその見出しを
  バージョン番号に書き換えるため、何も抜き出せていませんでした。タグのバージョンの節
  （`## [X.Y.Z]`）を読むように直し、節が見つからなければリリースを中止します。

## [0.2.1] — 2026-06-21

### 変更

- ブランディング刷新: Phoenix Framework のデフォルト UI（Flame ロゴ、ナビバーの
  バージョンバッジ、`· Phoenix Framework` タイトル接尾辞、未参照のウェルカム画面）を
  Ayumi 用に差し替え。新ロゴは「歩」字の止2つを抽象化した2つの斜めピル（深緑＋柿渋
  差し色）。ナビバーは「歩み AYUMI」のワードマーク化。SVG favicon を追加し、
  `<html lang="ja">` に変更。ネットワーク切断時のフラッシュ文言（gettext キー）も
  日本語化しました。
- 認証 UI の日本語化: `phx.gen.auth` ジェネレータが残した英語 UI（ログイン画面、
  アカウント設定画面、ログイン／ログアウト／パスワード変更／認証必須・再認証必須の
  フラッシュメッセージ）を CLAUDE.md の方針（User-facing strings are in Japanese）に
  揃えて日本語化しました。関連テストのアサーションも追従。

### 削除

- 未参照の Phoenix ウェルカム画面の死コード（`PageController` / `PageHTML` /
  `home.html.heex`）を削除。

## [0.2.0] — 2026-06-21

### 追加

- **出欠・実績記録票（attendance_record）**: 利用者ごとの日々の出欠・サービス提供を
  追記専用ログとして記録。`Ayumi.Plans.AttendanceRecord` スキーマ（`service_user_id` /
  `service_date` / `provision_type` / `pickup` / `dropoff` / `start_time` / `end_time` /
  `note` / `recorded_by_id` / `recorded_at`、`updated_at` なし）と
  `(service_user_id, service_date)` 複合インデックスを追加。訂正も新しい行として
  追記し、月次集計は同じ日付で最新行を採用します。
- **`Ayumi.Plans.ProvisionType` 列挙体**: `commute / offsite_work / offsite_support /
  absence / absence_support`（通所 / 施設外就労 / 施設外支援 / 欠席 / 欠席時対応）。
  `all/0` `label/1` `options/0` に加え、利用日数算定対象の `billable/0`、施設外集計
  対象の `offsite/0` を提供（記録票での別掲・集計の定義を一元化）。
- **Plans コンテキスト**: `change_attendance_record/2`・`create_attendance_record/2`
  （append-only。記録者・記録時刻はサーバ側で付与）・`list_attendance_records/3`
  （月境界での絞り込み、`month_bounds` ヘルパ）・`build_attendance_sheet/3`
  （ログを畳み込んで `AttendanceSheet` を返す純関数的導出）を追加。
- **`Ayumi.Plans.AttendanceSheet` 構造体**: 1利用者・1か月の実績記録票を表す導出
  データ（`lines: [%{date, record}]` と `totals: %{billable_days, offsite_days,
  pickup_count, dropoff_count, absence_support_count}`）。保存はしない。
- **出欠入力 LiveView**（`AyumiWeb.AttendanceLive.Index`、`/service_users/:service_user_id/attendance`）:
  1利用者・1か月分を1日1行の月次グリッドで入力。年月の前後ナビゲーション、開始時刻 ≤
  終了時刻のバリデーション、保存時の append（更新はしない）。全認証スタッフが利用可能。
- **実績記録票の印刷ビュー**（`AyumiWeb.AttendanceLive.Sheet`、`/service_users/:service_user_id/attendance/sheet`）:
  A4 印刷向けレイアウト（`@page { size: A4; margin: 12mm }`、ツールバーは `print:hidden`）。
  合計行は `AttendanceSheet.totals` をそのまま表示し、画面側で再計算しません。
  事業所名・事業所番号は `:ayumi, :facility` 設定（未設定なら空欄）から読み出し。
- **年月パラメータ解釈の共通化**（`AyumiWeb.AttendanceLive.MonthParams`）: Index と
  Sheet で重複していた `year` / `month` の解釈・既定値補完を1モジュールに集約。
- **利用者詳細ページからの導線**: `ServiceUserLive.Show` に「出欠・実績記録票」へのリンクを
  追加（集約表示の他項目には変更なし）。
- **設定ひな型**: `config/config.exs` に `:ayumi, :facility`（事業所名・事業所番号）の
  コメントテンプレートを追加。印刷ビューのヘッダで参照され、未設定なら空欄になります。

## [0.1.6] — 2026-06-20

### 修正

- DB バックアップで「空き名選定」と `VACUUM INTO` 実行が別ステップに分かれており、
  同一秒に複数プロセスが並行で `Ayumi.Backups.create_backup/2` を呼ぶと、全員が
  同じ空き名を選んだ後で1件だけ成功し、他は `VACUUM INTO failed: table ...
  already exists` 等で失敗するレース問題を修正。選定と VACUUM を
  `vacuum_attempt/3` + `try_vacuum_into/4` の1つのリトライループに統合し、
  VACUUM 失敗時はエラーメッセージ文字列ではなく出力先ファイルの存在で次
  サフィックスへ進むか中断するかを判定します。連続実行の高速パス（既存名は
  VACUUM を試さず即次へ）と上限 `@max_collision_retries 16` は維持。

## [0.1.5] — 2026-06-20

### 追加

- **DB バックアップ機能**: サービス管理責任者専用の DB バックアップツールを追加。
  Mix タスク（`mix ayumi.backup [出力先]`）と LiveView 画面（`/admin/backup`、
  `:require_manager`）から、稼働中の SQLite DB を SQLite の `VACUUM INTO` で
  整合的なファイルとして書き出します。`Ayumi.Backups` コンテキストが保存先の検証
  （存在・書込権限・稼働中 DB と別ディレクトリ）、タイムスタンプ付きファイル名の
  生成、同一秒で再実行されたときの `_1`, `_2` … サフィックスによる衝突回避を
  担います。
- バックアップ画面の成功表示に、保存先パス・サイズ・保存時刻(UTC 表記)を
  表示し、画面上部に成功/失敗のフラッシュ通知も出るようにしました。

### 修正

- バックアップ画面が `Layouts.app` で包まれておらず、`put_flash` が
  `<.flash_group>` に届かないため成功/失敗のフラッシュが表示されていなかった
  問題を修正。
- バックアップファイル名が秒精度のタイムスタンプのみで、同じ秒に2回実行すると
  `VACUUM INTO` が `output file already exists` で失敗していた問題を修正
  （`_1`, `_2` … サフィックスで空き名を探索）。上限 16 回で `{:error, ...}`
  を返し、保存先ディレクトリが既存ファイルで埋まっていた場合の無限再帰を
  防止します。

## [0.1.4] — 2026-06-20

### 修正

- 退所済み利用者が支援記録の一覧・新規作成で選択可能だった問題を修正。
- 退所済み利用者に対して支援計画を作成できた問題を修正。
- 支援計画作成時の退所チェックに TOCTOU 競合が残っていた問題をガード追加で修正。
- LiveView 経由の支援記録作成で `Ecto.CastError` が発生する問題を修正。

### ドキュメント

- README の書き出しをアプリの現在の機能範囲に合わせて更新。

## [0.1.3] — 2026-06-20

### 追加

- ダッシュボードに受給者証期限アラートを追加（超過・60日以内を表示）。
- 支援記録（`support_record`）: 利用者ごとの支援記録を追記専用ログとして記録。
  カテゴリ（作業・生活・健康・面談・その他）分類、利用者別・日付範囲でのフィルタ、
  記録者・日時の自動付与。`/support_records` で全体一覧・新規作成。
- 利用者まとめ画面（`ServiceUserLive.Show` の拡張）: 利用者詳細ページに期限バッジ
  （受給者証・モニタリング期限の超過/近接表示）、現行計画と目標の最新進捗、
  進捗・フェーズ履歴（最近20件）、支援記録（最近20件）を集約表示。スキーマ変更なし。
- macOS (Apple Silicon) ビルド済みバイナリの CI リリース: `v*` タグ push 時に
  `macos-14` ランナーで Mix release をビルドし、tar.gz として GitHub Release に添付。
  Windows 版と同時にリリースされます。

## [0.1.2] — 2026-06-20

### 追加

- Web Notifications によるモニタリング期限ナッジ: ダッシュボード表示時にブラウザの通知許可を
  取得し、超過・近接の件数を OS デスクトップ通知で表示します（`DeadlineNotifier` JS hook）。
  ブラウザごとの許可が前提のため、画面内リストが引き続き保証層です。
- Windows ビルド済みバイナリの CI リリース: `v*` タグ push 時に GitHub Actions の Windows
  ランナーで Mix release をビルドし、zip として GitHub Release に添付。利用者は Elixir/OTP
  のインストールなしで起動できます。
- `Ayumi.Release` モジュール: ビルド済みリリースから `bin/ayumi eval` 経由で
  マイグレーション（`migrate/0`）と職員アカウント作成（`create_user/0`）を実行するヘルパー。

## [0.1.1] — 2026-06-20

### 追加

- 職員認証（`phx.gen.auth`）: メールアドレス＋パスワードでのログイン、
  アカウント設定（メール・パスワード変更）。
- 利用者（service_user）管理: 一覧・新規登録・編集・詳細表示、基本情報、
  障害者手帳（disability_certificate）。
- 支援計画（support_plan）の作成・詳細表示と、短期目標（goal）。
- 短期目標の進捗更新ログ（`goal_progress`）: 計画詳細画面で goal ごとの現在進捗、
  進捗記録フォーム、履歴を表示。現在進捗は最新の追記行から導出します。
- 計画段階の遷移ログ（`plan_phase_event`）: 計画詳細画面で現在ステージ、ステージ記録フォーム、
  履歴を表示。現在ステージは最新の追記行から導出します。
- モニタリング期限ダッシュボード: 認証済みトップ `/` で、全利用者の現行計画から超過・30日以内の
  モニタリング予定を表示し、ログイン職員の担当分を先頭に並べます。
- 本体テーブルの同時編集安全化（楽観ロック）: `service_users` / `support_plans` / `goals` に
  `lock_version` を追加し、`Ayumi.Plans.update_service_user/2` で `optimistic_lock` により
  「黙った上書き（ロスト・アップデート）」を検知。利用者編集画面では競合時に `{:error, :stale}`
  を検出して最新を再読込し、再編集を促します（自動マージはしません）。
- 編集中プレゼンス表示（`AyumiWeb.Presence`）: 同じ利用者を別のスタッフが編集しているとき、
  編集画面に「○○さんが編集中」の警告を表示します（助言。保存自体は可能）。`Ayumi.PubSub` 上で
  動作し、外部依存はありません。
- オフライン向けの職員アカウント作成: `Ayumi.Accounts.register_staff_user/1`、
  および `mix ayumi.create_user` タスク。
- 初期化用の開発シード（デモ職員＋サンプル利用者・支援計画・目標、`MIX_ENV=dev` 限定・冪等）。
  `mix setup` / `mix ecto.reset` で実行。
- ロール分離（サービス管理責任者 `manager` / 支援者 `supporter`）: `users` テーブルに `role`
  カラムを追加（デフォルト `supporter`）。利用者・支援計画の作成・編集はサービス管理責任者のみに
  制限し、進捗記録・閲覧は全職員が可能。`Ayumi.Accounts.Role` 列挙モジュール、
  `Scope.manager?/1` による認可判定、`on_mount(:require_manager)` によるルート保護、
  UI 上のボタン・フォームのロール表示制御を追加。`mix ayumi.create_user` に `--role` オプション
  を追加。
- プロジェクトドキュメント: README、LICENSE（Apache-2.0）、NOTICE、CONTRIBUTING、SECURITY、
  CODE_OF_CONDUCT、Issue／PR テンプレート、本 CHANGELOG。

### 変更

- UI 文字列の gettext 化: Web 層（LiveView／共有レイアウト）に散在していた日本語文字列を
  `gettext/1`（`AyumiWeb.Gettext`、日本語をそのまま msgid）に集約し、`priv/gettext/default.pot`
  を抽出しました。未翻訳時は msgid を返すため、表示文字列は変更ありません。enum ラベル・changeset
  の検証メッセージ・CLI（`mix ayumi.create_user`）は対象外（既に集約済み／別レイヤー）。

### 削除

- Web のセルフ登録ページ（`/users/register`）と、メールのマジックリンク認証（ログイン・確認の
  ルート／LiveView）。アカウント作成はオフライン専用（`mix ayumi.create_user` / シード）、Web から
  のログインはメールアドレス＋パスワードのみになりました。

### セキュリティ

- LAN／ローカル限定アクセスの強制（`AyumiWeb.LanOnly`）。ループバックとプライベート／LAN レンジ
  以外の送信元 IP からの HTTP 接続を 403 で拒否し、LiveView の WebSocket 接続も同じ基準で遮断。
  本番は `check_origin: false`（LAN の IP 直アクセス向け。送信元 IP 制限で担保）、dev は全
  インターフェースにバインド。

[未リリース]: https://github.com/SilentMalachite/Ayumi/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/SilentMalachite/Ayumi/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/SilentMalachite/Ayumi/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/SilentMalachite/Ayumi/compare/v0.1.6...v0.2.0
[0.1.6]: https://github.com/SilentMalachite/Ayumi/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/SilentMalachite/Ayumi/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/SilentMalachite/Ayumi/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/SilentMalachite/Ayumi/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/SilentMalachite/Ayumi/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/SilentMalachite/Ayumi/releases/tag/v0.1.1
