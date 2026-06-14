# 歩み（Ayumi）

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**就労継続支援B型** 事業所向けの、個別支援計画 進捗トラッカーです。
支援スタッフが各利用者の個別支援計画の状況を記録し、短期目標の進み具合を残し、
近づくモニタリング期限を見落とさないようにすることを目的としています。

名前の「歩み」は設計思想を表しています。利用者一人ひとりの歩みを **追記専用のログ**
として記録し、その最新行を「現在の状態」として導出します。状態は上書きせず、訂正も
新しい行として残すため、福祉記録としての履歴が失われません。

- 利用者数: 約35名 / 支援スタッフ: 約6名 を想定した小規模・単一事業所向け。
- インターネット非依存。事業所内 LAN だけで完結します。

## 主な機能

### 実装済み

- **職員認証**（`phx.gen.auth` ベース）: メールアドレス＋パスワードでのログイン、アカウント設定
  （メール・パスワード変更）。アカウント作成は管理者によるオフライン操作のみ（Web セルフ登録と
  メールのマジックリンク認証は無効化）。
- **利用者（service_user）管理**: 一覧・新規登録・編集・詳細表示。基本情報（氏名・フリガナ・
  生年月日・連絡先・受給者証・通院先など）と、**障害者手帳（disability_certificates）** の登録。
- **支援計画（support_plan）**: 利用者ごとの計画期間・担当者・長期目標・次回モニタリング予定日の
  作成と詳細表示。
- **短期目標（goal）**: 支援計画にひもづく短期目標。
- **オフライン前提の職員アカウント初期化**: メール不要で確定済みアカウントを直接作成
  （`mix ayumi.create_user` と開発用シード）。

### 今後（未実装）

- `goal_progress` — 短期目標の進捗更新ログ（最も使う画面）。最新行から現在の進捗を導出。
- `plan_phase_event` — 計画のライフサイクル段階の遷移ログ。
- **モニタリング期限ダッシュボード** — 近接・超過の期限をトップに表示。

> 設計の詳細・ドメインの考え方・実装順は [`CLAUDE.md`](CLAUDE.md) を参照してください。

## 技術スタック

- **Elixir + Phoenix + Phoenix LiveView**（Phoenix 1.8 / LiveView 1.1）
- **Ecto + SQLite**（`ecto_sqlite3`。PostgreSQL ではありません）。WAL モード・外部キー有効。
- 認証は `phx.gen.auth`、パスワードハッシュは `bcrypt_elixir`。
- アセットは `esbuild` + `tailwind`（Mix 管理のため Node.js のインストールは不要）。
- HTTP サーバは `bandit`。
- 外部サービスなし: クラウド・メール配信・メッセージキュー・プッシュ通知・ジョブ基盤は使いません。

## 動作環境（デプロイ構成）

**単一ホスト + LAN** を前提に設計しています。

- 事業所の1台の PC が Phoenix サーバを動かし、唯一の SQLite ファイルを所有します。
- 他のスタッフは自分の端末のブラウザから LAN 経由でアクセスします（例: `http://<ホストIP>:4000`）。
- アプリは完全にオフラインで動作します。実行時にインターネットへの依存はありません。
- **LAN／ローカル限定。** LAN／ローカル以外の送信元 IP からの接続は `AyumiWeb.LanOnly`
  （HTTP の plug ＋ LiveView の `on_mount`）が 403 で拒否します。全インターフェースにバインド
  していても、外部（インターネット）からは利用できません。

この構成から導かれる **厳守事項**:

- SQLite ファイルは、起動中のアプリ1インスタンスだけが所有します。複数プロセス・複数マシンから
  同時に開く前提の設計をしないでください。
- SQLite ファイルをネットワーク共有（SMB/NFS）やクラウド同期フォルダ（OneDrive / iCloud /
  Dropbox）に置かないでください。同時アクセスで破損します。ホストのローカルディスクに置きます。

## 必要要件

- Elixir 1.15 以上（および対応する Erlang/OTP）
- SQLite ドライバ（`ecto_sqlite3` → `exqlite`）はビルド済みバイナリを利用するため、通常は
  C コンパイラ不要です（未対応プラットフォームではソースからビルドするため、C ツールチェーンが
  必要になる場合があります）。

## セットアップ

依存関係の取得から DB 作成・マイグレーション・初期データ投入・アセットビルドまでを一括で行います。

```bash
mix setup
```

`mix setup` は次を順に実行します（`mix.exs` のエイリアス）:

1. `deps.get` — 依存関係の取得
2. `ecto.setup` — DB 作成 → マイグレーション → `priv/repo/seeds.exs` 実行
3. `assets.setup` / `assets.build` — esbuild / tailwind の導入とビルド

## 起動

```bash
mix phx.server
# または IEx 上で
iex -S mix phx.server
```

ブラウザで [`http://localhost:4000`](http://localhost:4000) を開きます。

> **LAN の他の端末から接続:** 開発・本番とも全インターフェースにバインドしてあり、LAN の他端末から
> `http://<ホストIP>:4000` でアクセスできます。LAN／ローカル以外の送信元 IP からの接続は
> `AyumiWeb.LanOnly` が 403 で拒否するため、インターネットからは利用できません。ポートは `PORT`
> 環境変数で変更できます。

## 初期化と職員アカウント

このアプリはオフライン運用でメール送信を行いません。そのため Web のセルフ登録ページ
（`/users/register`）とメールのマジックリンク認証（ログイン・確認）は**無効化**してあり、
**職員アカウントの作成は管理者によるオフライン操作のみ**です（確定済み・パスワード付きで直接作成）。
Web からのログインはメールアドレス＋パスワードのみです。

### DB を初期状態に戻す

```bash
mix ecto.reset   # drop → create → migrate → seed
```

### 職員アカウントを作成する（本番・事業所 PC 向け）

```bash
mix ayumi.create_user
# 対話入力。引数指定も可能（パスワードはシェル履歴に残る点に注意）:
mix ayumi.create_user --email staff@example.com --name "支援 太郎" --password "12文字以上のパスワード"
```

### 開発用のシードアカウント

開発環境（`MIX_ENV=dev`）でのみ、デモ用の職員アカウントとサンプル利用者・支援計画・目標が
投入されます（`test`・`prod` では投入されず、`mix ayumi.create_user` の案内が表示されます）。

| メールアドレス | パスワード |
| --- | --- |
| `admin@ayumi.local` | `ayumi-dev-1234` |
| `staff@ayumi.local` | `ayumi-dev-1234` |

シードは冪等です（職員はメールで照合、サンプルデータは利用者が0件のときのみ投入）。

## 開発

```bash
mix test       # テスト（DB を作成・マイグレーションしてから実行）
mix review     # 品質ゲート: format 確認 → 警告をエラー扱いでコンパイル → credo → test
mix precommit  # コミット前チェック: コンパイル → 未使用依存の検出 → format → test
```

`mix review` が通ること（テストを含む）が「完了」の基準です。

開発時のみ、次の補助ルートが有効です（`config :ayumi, dev_routes: true`）:

- `/dev/dashboard` — Phoenix LiveDashboard
- `/dev/mailbox` — Swoosh のローカルメールプレビュー

## ドメインモデル

4つのテーブルで構成します。2つは「本体」（めったに編集しない）、2つは「追記専用ログ」です。

- `support_plan` — 計画期間ごとの個別支援計画（担当者・期間・長期目標・次回モニタリング予定日）。
- `goal` — `support_plan` にひもづく短期目標。
- `plan_phase_event` —（今後）計画の段階遷移を1行ずつ記録する追記専用ログ。
- `goal_progress` —（今後）短期目標の進捗更新を1行ずつ記録する追記専用ログ。

**追記専用の原則:** 状態変更は既存行の上書きではなく新しい行で記録します。「現在の状態」は
保存せず、最新行から導出します（純粋関数でログを畳み込む形）。

計画ライフサイクル段階（`plan_phase_event.stage`、順序付き）:

`assessment`（アセスメント）→ `draft`（計画原案）→ `support_meeting`（個別支援会議）→
`consent`（説明・同意・交付）→ `in_progress`（支援の実施）→ `monitoring`（モニタリング）→
`review`（見直し）

詳細は [`CLAUDE.md`](CLAUDE.md) を参照してください。

## ドキュメント

- [貢献ガイド（CONTRIBUTING）](CONTRIBUTING.md)
- [セキュリティポリシー（SECURITY）](SECURITY.md)
- [行動規範（CODE OF CONDUCT）](CODE_OF_CONDUCT.md)
- [変更履歴（CHANGELOG）](CHANGELOG.md)

## ライセンス

[Apache License 2.0](LICENSE) で提供されます。Copyright 2026 Silent Malachite。
詳細は [`LICENSE`](LICENSE) および [`NOTICE`](NOTICE) を参照してください。
