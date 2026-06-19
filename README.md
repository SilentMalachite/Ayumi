# 歩み（Ayumi）

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![CI](https://github.com/SilentMalachite/Ayumi/actions/workflows/ci.yml/badge.svg)](https://github.com/SilentMalachite/Ayumi/actions/workflows/ci.yml)

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
- **短期目標の進捗（goal_progress）**: 目標ごとの進捗を追記専用ログとして記録し、最新行から
  現在進捗を導出。計画詳細画面で現在進捗・記録フォーム・履歴を確認できます。
- **計画ライフサイクル（plan_phase_event）**: 計画段階の遷移を追記専用ログとして記録し、
  最新行から現在ステージを導出。計画詳細画面で現在ステージ・記録フォーム・履歴を確認できます。
- **モニタリング期限ダッシュボード**: ログイン後トップ `/` で、全利用者の現行計画から
  超過・30日以内のモニタリング予定を表示。ログイン職員の担当分を先頭にし、期限の近い順に並べます。
- **同時編集の安全化**: 複数スタッフが同じ本体データ（利用者など）を同時に編集しても、片方の
  変更が黙って消えないよう **楽観ロック（`lock_version`）** で競合を検知し、競合時は最新を
  読み込んで再編集を促します（自動マージはしません）。さらに **編集中プレゼンス表示**
  （`AyumiWeb.Presence`）で「○○さんが編集中」を事前に警告します（外部依存なし・完全オフライン）。
- **オフライン前提の職員アカウント初期化**: メール不要で確定済みアカウントを直接作成
  （`mix ayumi.create_user` と開発用シード）。
- **ロール分離**（サービス管理責任者 / 支援者）: 利用者と支援計画の作成・編集はサービス管理責任者
  （`manager`）のみ。進捗記録・ステージ遷移・閲覧は全職員が可能。
- **モニタリング期限の OS 通知（Web Notifications）**: ダッシュボード表示時に、ブラウザの通知許可
  があれば超過・近接の件数を OS デスクトップ通知で表示します（`DeadlineNotifier` JS hook）。
  ブラウザごとの許可が前提のため、画面内リストが引き続き保証層です。
- **Windows ビルド済みバイナリ**: GitHub Releases から zip をダウンロードするだけで、Elixir/OTP の
  インストールなしで起動できます。`v*` タグ push 時に GitHub Actions が自動ビルドします。

> 設計の詳細・ドメインの考え方・実装順は [`CLAUDE.md`](CLAUDE.md) を参照してください。

## 技術スタック

- **Elixir + Phoenix + Phoenix LiveView**（Phoenix 1.8 / LiveView 1.1）
- **Ecto + SQLite**（`ecto_sqlite3`。PostgreSQL ではありません）。WAL モード・外部キー有効。
- 認証は `phx.gen.auth`、パスワードハッシュは `bcrypt_elixir`。
- アセットは `esbuild` + `tailwind`（Mix 管理のため Node.js のインストールは不要）。
- HTTP サーバは `bandit`。
- 外部サービスなし: クラウド・メール配信・メッセージキュー・プッシュ通知・ジョブ基盤は使いません。
- ユーザー向け文言は `gettext`（`AyumiWeb.Gettext`、日本語を msgid）で集約管理（`priv/gettext/default.pot`）。

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
mix ayumi.create_user --email staff@example.com --name "支援 太郎" --password "12文字以上のパスワード" --role manager
```

`--role` には `manager`（サービス管理責任者）または `supporter`（支援者、デフォルト）を指定します。
対話モードではメニューから選択できます。

### 開発用のシードアカウント

開発環境（`MIX_ENV=dev`）でのみ、デモ用の職員アカウントとサンプル利用者・支援計画・目標が
投入されます（`test`・`prod` では投入されず、`mix ayumi.create_user` の案内が表示されます）。

| メールアドレス | パスワード | ロール |
| --- | --- | --- |
| `admin@ayumi.local` | `ayumi-dev-1234` | `manager`（サービス管理責任者） |
| `staff@ayumi.local` | `ayumi-dev-1234` | `supporter`（支援者） |

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

## 本番デプロイ

事業所の PC に Ayumi をデプロイする手順です。

### 方法 A: ビルド済みバイナリ（Windows・推奨）

Elixir や Erlang のインストールは不要です。

1. [GitHub Releases](https://github.com/SilentMalachite/Ayumi/releases) から
   最新の `ayumi-vX.Y.Z-windows-x86_64.zip` をダウンロードし、任意のフォルダに展開します。

2. `start.bat.example` を `start.bat` にコピーし、テキストエディタで
   `SECRET_KEY_BASE=` の行を編集します（64文字以上のランダム文字列）。

3. 職員アカウントを作成します:
   ```
   bin\ayumi.bat eval "Ayumi.Release.create_user()"
   ```

4. `start.bat` を実行するとサーバが起動します。

ブラウザで `http://localhost:4000` を開きます。LAN 上の他の端末からは
`http://（この PC の IP アドレス）:4000` でアクセスできます。

**バージョンアップ:** サーバを停止 → 新しい zip を同じフォルダに上書き展開 →
`start.bat` で起動（`data/` フォルダと `start.bat` は上書きしないでください）。

### 方法 B: ソースからビルド（Windows / macOS）

Elixir と Erlang/OTP のインストールが必要です。

#### 前提条件

- **Windows 10/11** または **macOS**
- **インターネット接続**（初回セットアップ時のみ。運用時は不要）
- **Erlang/OTP と Elixir** がインストール済み
  - [Elixir 公式サイト](https://elixir-lang.org/install.html) からインストールしてください。
  - macOS: `brew install elixir`（[Homebrew](https://brew.sh) 利用時）

#### 初回セットアップ

1. [GitHub Releases](https://github.com/SilentMalachite/Ayumi/releases) から
   最新バージョンの Source code をダウンロードし、任意のフォルダに展開します。

2. セットアップスクリプトを実行します:

   **Windows（コマンドプロンプト）:**
   ```
   setup.bat
   ```

   **macOS（ターミナル）:**
   ```bash
   ./setup.sh
   ```

3. 起動スクリプトのテンプレートをコピーし、`SECRET_KEY_BASE` を設定します:

   **Windows:**
   ```
   copy start.bat.example start.bat
   ```

   **macOS:**
   ```bash
   cp start.sh.example start.sh
   ```

   コピーしたファイルをテキストエディタで開き、`SECRET_KEY_BASE=` の行を編集します。
   値は以下のコマンドで生成できます:

   ```
   mix phx.gen.secret
   ```

4. 職員アカウントを作成します:

   **Windows:**
   ```
   set MIX_ENV=prod
   set DATABASE_PATH=data\ayumi.db
   mix ayumi.create_user
   ```

   **macOS:**
   ```bash
   MIX_ENV=prod DATABASE_PATH=data/ayumi.db mix ayumi.create_user
   ```

#### 起動

**Windows:**
```
start.bat
```

**macOS:**
```bash
./start.sh
```

ブラウザで `http://localhost:4000` を開きます。LAN 上の他の端末からは
`http://（この PC/Mac の IP アドレス）:4000` でアクセスできます。

#### バージョンアップ

1. サーバを停止します（Ctrl+C）。
2. 新しいバージョンの Source code をダウンロードし、同じフォルダに上書き展開します。
3. セットアップスクリプトを再実行します（DB はそのまま引き継がれ、マイグレーションが適用されます）。
4. 起動スクリプトで起動します。

> **注意:** `start.bat` / `start.sh` と `data/` フォルダ（DB ファイル）は上書きしないでください。

## ドメインモデル

中心モデルは、2つの「本体」（めったに編集しない）と2つの「追記専用ログ」で構成します。

- `support_plan` — 計画期間ごとの個別支援計画（担当者・期間・長期目標・次回モニタリング予定日）。
- `goal` — `support_plan` にひもづく短期目標。
- `goal_progress` — 短期目標の進捗更新を1行ずつ記録する追記専用ログ。
- `plan_phase_event` — 計画の段階遷移を1行ずつ記録する追記専用ログ。

**追記専用の原則:** 状態変更は既存行の上書きではなく新しい行で記録します。「現在の状態」は
保存せず、最新行から導出します（純粋関数でログを畳み込む形）。

計画ライフサイクル段階（`plan_phase_event.stage`、順序付き）:

`assessment`（アセスメント）→ `draft`（計画原案）→ `support_meeting`（個別支援会議）→
`consent`（説明・同意・交付）→ `in_progress`（支援の実施）→ `monitoring`（モニタリング）→
`review`（見直し）

短期目標進捗（`goal_progress.stage`）:

`not_started`（未着手） / `working`（取組中） / `partially_met`（一部達成） /
`mostly_met`（概ね達成） / `met`（達成）

詳細は [`CLAUDE.md`](CLAUDE.md) を参照してください。

## ドキュメント

- [貢献ガイド（CONTRIBUTING）](CONTRIBUTING.md)
- [セキュリティポリシー（SECURITY）](SECURITY.md)
- [行動規範（CODE OF CONDUCT）](CODE_OF_CONDUCT.md)
- [変更履歴（CHANGELOG）](CHANGELOG.md)

## ライセンス

[Apache License 2.0](LICENSE) で提供されます。Copyright 2026 Silent Malachite。
詳細は [`LICENSE`](LICENSE) および [`NOTICE`](NOTICE) を参照してください。
