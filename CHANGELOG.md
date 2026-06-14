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
- オフライン向けの職員アカウント作成: `Ayumi.Accounts.register_staff_user/1`、
  および `mix ayumi.create_user` タスク。
- 初期化用の開発シード（デモ職員＋サンプル利用者・支援計画・目標、`MIX_ENV=dev` 限定・冪等）。
  `mix setup` / `mix ecto.reset` で実行。
- プロジェクトドキュメント: README、LICENSE（Apache-2.0）、NOTICE、CONTRIBUTING、SECURITY、
  CODE_OF_CONDUCT、Issue／PR テンプレート、本 CHANGELOG。

### 今後の予定（未実装）

- `goal_progress` — 短期目標の進捗更新ログ。
- `plan_phase_event` — 計画段階の遷移ログ。
- モニタリング期限ダッシュボード。

---

本プロジェクトはまだ正式リリース（タグ付き）を行っていません。最初の安定版で `0.1.0` として
本セクションを確定する予定です。

[未リリース]: https://github.com/SilentMalachite/Ayumi/commits/main
