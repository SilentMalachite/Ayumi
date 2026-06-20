# 歩み（Ayumi）

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![CI](https://github.com/SilentMalachite/Ayumi/actions/workflows/ci.yml/badge.svg)](https://github.com/SilentMalachite/Ayumi/actions/workflows/ci.yml)

**就労継続支援B型** 事業所向けの業務支援アプリです。
利用者情報の管理、個別支援計画の作成と進捗記録、日々の支援記録、
モニタリング期限・受給者証期限のアラートを一つの画面に集約し、
支援業務に必要な情報の記録・確認・共有をまとめて行えます。

名前の「歩み」は設計思想を表しています。支援計画の段階遷移、短期目標の進捗、
日々の支援記録——すべてを **追記専用のログ** として記録し、最新行から「現在の状態」を
導出します。過去の記録は上書きせず、訂正も新しい行として残すため、
福祉記録としての履歴が失われません。

- 利用者数: 約35名 / 支援スタッフ: 約6名 を想定した小規模・単一事業所向け。
- インターネット非依存。事業所内 LAN だけで完結します。
- Elixir/OTP 不要のビルド済みバイナリ（Windows / macOS）を配布しています。

## 主な機能

### 利用者管理

- **利用者（service_user）管理**: 一覧・新規登録・編集・詳細表示。
  - 基本情報: 氏名・フリガナ・生年月日・性別・連絡先・緊急連絡先。
  - 受給者証: 受給者証番号・支給市区町村・障害支援区分（区分1〜6）・支給量・有効期限。
  - 医療情報: 通院先・主治医・服薬情報。
  - 相談支援: 相談支援事業所・担当相談支援専門員。
  - **障害者手帳（disability_certificate）**: 種別（身体・療育・精神）・等級の登録。
  - **在籍ステータス**: 体験利用・在籍・休止・退所。退所者は利用者一覧で非表示（データは保持）。

### 支援計画・目標・進捗

- **支援計画（support_plan）**: 利用者ごとの計画期間・担当者・長期目標・次回モニタリング予定日の
  作成と詳細表示。
- **短期目標（goal）**: 支援計画にひもづく短期目標。
- **短期目標の進捗（goal_progress）**: 目標ごとの進捗を追記専用ログとして記録し、最新行から
  現在進捗を導出。計画詳細画面で現在進捗・記録フォーム・履歴を確認できます。
- **計画ライフサイクル（plan_phase_event）**: 計画段階の遷移を追記専用ログとして記録し、
  最新行から現在ステージを導出。計画詳細画面で現在ステージ・記録フォーム・履歴を確認できます。

### 支援記録

- **支援記録（support_record）**: 利用者ごとの日々の支援内容を追記専用ログとして記録。
  カテゴリ（作業・生活・健康・面談・その他）で分類し、利用者別・日付範囲でフィルタ可能。
  `/support_records` で全体一覧・新規作成。

### ダッシュボード・通知

- **モニタリング期限ダッシュボード**: ログイン後トップ `/` で、全利用者の現行計画から
  超過・30日以内のモニタリング予定を表示。ログイン職員の担当分を先頭にし、期限の近い順に並べます。
- **受給者証期限アラート**: ダッシュボードに受給者証の有効期限が超過・60日以内のアラートを表示。
- **モニタリング期限の OS 通知（Web Notifications）**: ダッシュボード表示時に、ブラウザの通知許可
  があれば超過・近接の件数を OS デスクトップ通知で表示します（`DeadlineNotifier` JS hook）。
  ブラウザごとの許可が前提のため、画面内リストが引き続き保証層です。

### 利用者まとめ画面

- 利用者詳細ページ（`/service_users/:id`）に、基本情報に加えて
  期限バッジ（受給者証・モニタリング期限の超過/近接）、現行計画と目標の最新進捗、
  進捗・フェーズ履歴（最近20件）、支援記録（最近20件）を集約表示。1画面で利用者の
  全体像を把握できます。

### 認証・認可

- **職員認証**（`phx.gen.auth` ベース）: メールアドレス＋パスワードでのログイン、アカウント設定
  （メール・パスワード変更）。アカウント作成は管理者によるオフライン操作のみ（Web セルフ登録と
  メールのマジックリンク認証は無効化）。
- **ロール分離**（サービス管理責任者 / 支援者）: 利用者と支援計画の作成・編集はサービス管理責任者
  （`manager`）のみ。進捗記録・ステージ遷移・支援記録の作成・閲覧は全職員が可能。

### データ安全性

- **同時編集の安全化**: 複数スタッフが同じ本体データ（利用者など）を同時に編集しても、片方の
  変更が黙って消えないよう **楽観ロック（`lock_version`）** で競合を検知し、競合時は最新を
  読み込んで再編集を促します（自動マージはしません）。さらに **編集中プレゼンス表示**
  （`AyumiWeb.Presence`）で「○○さんが編集中」を事前に警告します（外部依存なし・完全オフライン）。
- **LAN／ローカル限定**: LAN／ローカル以外の送信元 IP からの接続は `AyumiWeb.LanOnly`
  （HTTP の plug ＋ LiveView の `on_mount`）が 403 で拒否します。

### 運用ツール

- **オフライン前提の職員アカウント初期化**: メール不要で確定済みアカウントを直接作成
  （`mix ayumi.create_user` と開発用シード）。
- **DB バックアップ**: サービス管理責任者専用。Web 画面（`/admin/backup`）と
  Mix タスク（`mix ayumi.backup [出力先]`、ソースビルド向け）から、稼働中の
  SQLite DB を SQLite の `VACUUM INTO` で整合的なファイルとして書き出します。
  タイムスタンプ付きのファイル名（衝突時は `_1`, `_2` … と退避）で保存し、
  保存先パス・サイズ・保存時刻（UTC）を表示します。ビルド済みリリースでも
  Web 画面から実行できます。
- **ビルド済みバイナリ**: GitHub Releases から Windows（zip）・macOS Apple Silicon（tar.gz）を
  ダウンロードするだけで、Elixir/OTP のインストールなしで起動できます。`v*` タグ push 時に
  GitHub Actions が自動ビルドします。

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

### 方法 A: ビルド済みバイナリ（推奨）

Elixir や Erlang のインストールは不要です。

[GitHub Releases](https://github.com/SilentMalachite/Ayumi/releases) から
お使いの OS に合ったアーカイブをダウンロードしてください:

| OS | ファイル名 | 形式 |
| --- | --- | --- |
| Windows (x86_64) | `ayumi-vX.Y.Z-windows-x86_64.zip` | zip |
| macOS (Apple Silicon) | `ayumi-vX.Y.Z-macos-arm64.tar.gz` | tar.gz |

#### Windows

1. zip を任意のフォルダに展開します。

2. `start.bat.example` を `start.bat` にコピーし、テキストエディタで
   `SECRET_KEY_BASE=` の行を編集します（64文字以上のランダム文字列）。

3. 職員アカウントを作成します:
   ```
   bin\ayumi.bat eval "Ayumi.Release.create_user()"
   ```

4. `start.bat` を実行するとサーバが起動します。

#### macOS (Apple Silicon)

1. tar.gz を任意のフォルダに展開します:
   ```bash
   tar xzf ayumi-vX.Y.Z-macos-arm64.tar.gz
   ```

2. `start.sh.example` を `start.sh` にコピーし、テキストエディタで
   `SECRET_KEY_BASE=` の行を編集します（64文字以上のランダム文字列）。

3. 職員アカウントを作成します:
   ```bash
   bin/ayumi eval "Ayumi.Release.create_user()"
   ```

4. `./start.sh` を実行するとサーバが起動します。

#### 共通

ブラウザで `http://localhost:4000` を開きます。LAN 上の他の端末からは
`http://（この PC/Mac の IP アドレス）:4000` でアクセスできます。

**バージョンアップ:** サーバを停止 → 新しいアーカイブを同じフォルダに上書き展開 →
起動スクリプトで起動（`data/` フォルダと `start.bat` / `start.sh` は上書きしないでください）。

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

中心モデルは、2つの「本体」（めったに編集しない）と3つの「追記専用ログ」で構成します。

- `support_plan` — 計画期間ごとの個別支援計画（担当者・期間・長期目標・次回モニタリング予定日）。
- `goal` — `support_plan` にひもづく短期目標。
- `goal_progress` — 短期目標の進捗更新を1行ずつ記録する追記専用ログ。
- `plan_phase_event` — 計画の段階遷移を1行ずつ記録する追記専用ログ。
- `support_record` — 利用者ごとの日々の支援記録を1行ずつ記録する追記専用ログ
  （カテゴリ・内容・記録者・日時）。

**追記専用の原則:** 状態変更は既存行の上書きではなく新しい行で記録します。「現在の状態」は
保存せず、最新行から導出します（純粋関数でログを畳み込む形）。

計画ライフサイクル段階（`plan_phase_event.stage`、順序付き）:

`assessment`（アセスメント）→ `draft`（計画原案）→ `support_meeting`（個別支援会議）→
`consent`（説明・同意・交付）→ `in_progress`（支援の実施）→ `monitoring`（モニタリング）→
`review`（見直し）

短期目標進捗（`goal_progress.stage`）:

`not_started`（未着手） / `working`（取組中） / `partially_met`（一部達成） /
`mostly_met`（概ね達成） / `met`（達成）

## ドキュメント

- [貢献ガイド（CONTRIBUTING）](CONTRIBUTING.md)
- [セキュリティポリシー（SECURITY）](SECURITY.md)
- [行動規範（CODE OF CONDUCT）](CODE_OF_CONDUCT.md)
- [変更履歴（CHANGELOG）](CHANGELOG.md)

## ライセンス

[Apache License 2.0](LICENSE) で提供されます。Copyright 2026 Silent Malachite。
詳細は [`LICENSE`](LICENSE) および [`NOTICE`](NOTICE) を参照してください。
