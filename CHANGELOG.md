# 変更履歴

本ファイルの記法は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に準拠し、
バージョニングは [セマンティック バージョニング](https://semver.org/lang/ja/) に従います。

## [未リリース]

### 追加

- 職員認証（`phx.gen.auth`）: メールアドレス＋パスワード／マジックリンクでのログイン、
  アカウント設定（メール・パスワード変更）。
- 利用者（service_user）管理: 一覧・新規登録・編集・詳細表示、基本情報、
  障害者手帳（disability_certificate）。
- 支援計画（support_plan）の作成・詳細表示と、短期目標（goal）。
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

### 今後の予定（未実装）

- `goal_progress` — 短期目標の進捗更新ログ。
- `plan_phase_event` — 計画段階の遷移ログ。
- モニタリング期限ダッシュボード。

---

本プロジェクトはまだ正式リリース（タグ付き）を行っていません。最初の安定版で `0.1.0` として
本セクションを確定する予定です。

[未リリース]: https://github.com/SilentMalachite/Ayumi/commits/main
