# CI 強化 + Mix Release + GitHub Releases 設計書

- 日付: 2026-06-19
- 対象: CI ワークフローの強化、Mix release 設定、GitHub Releases による配布
- ステータス: 承認済み（実装計画へ）

## 背景

Ayumi は事業所内の1台の Windows PC で動かす LAN 専用アプリ。現在の CI は Ubuntu で
`mix review` を走らせるのみで、リリースの仕組みがない。事業所 PC に確実にデプロイ
できるようにする。

## 制約

- **クロスコンパイル不可。** Elixir の Mix release はビルド環境と同一 OS/アーキテクチャ
  でしか動かない。Ubuntu CI でビルドしたバイナリは Windows では動かない。
- **事業所 PC は Windows。** Elixir/Erlang のインストールが必要。
- **インターネット接続は構築時のみ。** 依存の取得とビルドにはネット接続が要るが、
  運用時は不要。

## 設計

### 1. CI ワークフロー強化（`.github/workflows/ci.yml`）

既存の `mix review` ジョブに加え、**リリースビルド検証ジョブ**を追加する。

```yaml
jobs:
  mix-review:     # 既存。format / compile / credo / test
  release-build:  # 新規。MIX_ENV=prod でリリースが壊れていないことを検証
```

release-build ジョブ:
- `MIX_ENV=prod`
- `mix deps.get --only prod`
- `mix assets.deploy`（CSS/JS ミニファイ + digest）
- `mix release`（ビルドが通ることを確認。成果物は使わない — Ubuntu 用なので）
- `mix review` と並列実行（依存関係なし）

### 2. Mix release 設定

`mix.exs` に releases 設定を追加:

```elixir
releases: [
  ayumi: [
    include_executables_for: [:windows, :unix],
    cookie: "ayumi-release-cookie"
  ]
]
```

`rel/` ディレクトリに以下を配置:

- `rel/env.bat.eex` — Windows 用の環境変数テンプレート
- `rel/env.sh.eex` — Unix 用の環境変数テンプレート（開発・CI 用）

### 3. runtime.exs の修正

現在の `config/runtime.exs` は本番設定が cloud 向けのデフォルトのままになっている箇所を修正:

- `url:` の `scheme: "https"`, `port: 443` → `scheme: "http"`, `port: port`（LAN は HTTP）
- `PHX_HOST` のデフォルトを `"localhost"` に変更（LAN IP 直アクセスなので）
- DNS cluster query は不要なのでコメントアウト済みだが残す（害がないため）

### 4. GitHub Releases ワークフロー（`.github/workflows/release.yml`）

`v*` タグの push で発火:

1. CI（`mix review`）が通ることを前提条件にする（`needs: mix-review`ではなく、
   タグ push 時にも ci.yml が走るのでそちらに任せる）
2. `mix.exs` からバージョンを抽出
3. CHANGELOG.md から該当バージョンのセクションを抽出（未リリースセクションを使用）
4. `gh release create` でリリースを作成:
   - タイトル: `Ayumi v{version}`
   - ボディ: CHANGELOG 抜粋 + セットアップ手順リンク
   - ソースアーカイブは GitHub が自動添付

### 5. Windows 向けセットアップ・起動補助

`rel/` に以下のスクリプトを配置:

**`setup.bat`** — 初回セットアップ用:
```bat
@echo off
echo Ayumi セットアップ
mix deps.get --only prod
set MIX_ENV=prod
mix ecto.create
mix ecto.migrate
mix assets.deploy
mix release
echo セットアップ完了。start.bat で起動してください。
```

**`start.bat`** — 起動用:
```bat
@echo off
set DATABASE_PATH=%~dp0\data\ayumi.db
set SECRET_KEY_BASE=<generated>
set PHX_SERVER=true
set PORT=4000
_build\prod\rel\ayumi\bin\ayumi.bat start
```

README に Windows 向けデプロイ手順セクションを追加する。

### 6. 対象外

- Docker は使わない（事業所 PC に Docker を入れる運用負荷が高い）。
- CI での Windows ビルドは行わない（セットアップの不安定さ、ビルド時間の問題）。
- 自動アップデート機能は作らない（手動で新バージョンを取得・ビルド）。

## ファイル変更一覧

| ファイル | 変更 |
|---------|------|
| `mix.exs` | releases 設定追加 |
| `config/runtime.exs` | LAN 向けに url 設定修正 |
| `.github/workflows/ci.yml` | release-build ジョブ追加 |
| `.github/workflows/release.yml` | 新規: タグ push でリリース作成 |
| `rel/env.bat.eex` | 新規: Windows 用環境テンプレート |
| `rel/env.sh.eex` | 新規: Unix 用環境テンプレート |
| `rel/overlays/bin/server` | 新規: Unix 起動スクリプト |
| `rel/overlays/bin/server.bat` | 新規: Windows 起動スクリプト |
| `setup.bat` | 新規: Windows 初回セットアップ |
| `start.bat` | 新規: Windows 起動 |
| `README.md` | デプロイ手順セクション追加 |
