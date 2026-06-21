# 変更履歴

本ファイルの記法は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に準拠し、
バージョニングは [セマンティック バージョニング](https://semver.org/lang/ja/) に従います。

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

[未リリース]: https://github.com/SilentMalachite/Ayumi/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/SilentMalachite/Ayumi/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/SilentMalachite/Ayumi/compare/v0.1.6...v0.2.0
[0.1.6]: https://github.com/SilentMalachite/Ayumi/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/SilentMalachite/Ayumi/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/SilentMalachite/Ayumi/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/SilentMalachite/Ayumi/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/SilentMalachite/Ayumi/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/SilentMalachite/Ayumi/releases/tag/v0.1.1
