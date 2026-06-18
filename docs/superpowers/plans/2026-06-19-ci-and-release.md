# CI 強化 + Mix Release + GitHub Releases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CI にリリースビルド検証を追加し、Mix release + Windows 向け起動補助 + GitHub Releases ワークフローを整備して、事業所 PC へのデプロイを可能にする。

**Architecture:** 既存 CI (`mix review`) に `release-build` ジョブを並列追加。Mix release 設定と `rel/` overlays（server スクリプト）を追加。`v*` タグ push で GitHub Release を自動作成するワークフローを新設。事業所 PC (Windows) 向けに `setup.bat` / `start.bat` を提供。

**Tech Stack:** Elixir Mix release, GitHub Actions, bat スクリプト

## Global Constraints

- Elixir ~> 1.15, OTP 28（CI）
- SQLite（`ecto_sqlite3`）— DB ファイルはホストのローカルディスク
- LAN 専用（HTTP、HTTPS 不要）
- Windows が本番ターゲット（CI は Ubuntu で検証のみ、成果物は使わない）
- `mix review` が品質ゲート

---

### Task 1: Mix release 設定 + rel/ overlays

**Files:**
- Modify: `mix.exs` — releases 設定追加
- Create: `rel/overlays/bin/server` — Unix 起動スクリプト
- Create: `rel/overlays/bin/server.bat` — Windows 起動スクリプト
- Modify: `config/runtime.exs` — LAN 向け url 設定修正

**Interfaces:**
- Consumes: なし（最初のタスク）
- Produces: `mix release` がエラーなく完了すること。`_build/prod/rel/ayumi/bin/ayumi` が生成されること。

- [ ] **Step 1: mix.exs に releases 設定を追加**

`mix.exs` の `project/0` に releases キーを追加:

```elixir
def project do
  [
    app: :ayumi,
    version: "0.1.0",
    elixir: "~> 1.15",
    name: "Ayumi",
    description: "就労継続支援B型事業所向けの個別支援計画 進捗トラッカー",
    source_url: "https://github.com/SilentMalachite/Ayumi",
    package: package(),
    elixirc_paths: elixirc_paths(Mix.env()),
    start_permanent: Mix.env() == :prod,
    aliases: aliases(),
    deps: deps(),
    releases: releases(),
    compilers: [:phoenix_live_view] ++ Mix.compilers(),
    listeners: [Phoenix.CodeReloader]
  ]
end
```

新しい private 関数を追加（`package/0` の直後）:

```elixir
defp releases do
  [
    ayumi: [
      include_executables_for: [:windows, :unix],
      cookie: "ayumi-LAN-only-cookie"
    ]
  ]
end
```

- [ ] **Step 2: rel/overlays/bin/server を作成**

Phoenix の標準パターン。`PHX_SERVER=true` を設定してリリースを起動する:

```bash
#!/bin/sh
cd -P -- "$(dirname -- "$0")"
PHX_SERVER=true exec ./ayumi start
```

ファイルに実行権限を付与:

```bash
chmod +x rel/overlays/bin/server
```

- [ ] **Step 3: rel/overlays/bin/server.bat を作成**

```bat
@echo off
set PHX_SERVER=true
call "%~dp0\ayumi.bat" start
```

- [ ] **Step 4: config/runtime.exs を LAN 向けに修正**

prod ブロック内の endpoint 設定を修正。変更点:
- `PHX_HOST` デフォルトを `"localhost"` に（LAN IP 直アクセス向け）
- `url:` を HTTP + 実ポートに変更（HTTPS 不使用）

修正前:

```elixir
  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :ayumi, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :ayumi, AyumiWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
```

修正後:

```elixir
  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :ayumi, AyumiWeb.Endpoint,
    url: [host: host, port: port, scheme: "http"],
```

また、不要な `dns_cluster_query` 行を削除する。

- [ ] **Step 5: ローカルでリリースビルドを検証**

```bash
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
```

期待: エラーなく完了し、`_build/prod/rel/ayumi/bin/ayumi` が生成される。
`rel/overlays/bin/server` も `_build/prod/rel/ayumi/bin/server` にコピーされていること:

```bash
ls _build/prod/rel/ayumi/bin/server
```

- [ ] **Step 6: コミット**

```bash
git add mix.exs config/runtime.exs rel/
git commit -m "feat: add Mix release configuration for LAN deployment"
```

---

### Task 2: CI に release-build ジョブを追加

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: Task 1 の release 設定（`mix release` が通ること）
- Produces: CI で release ビルドが検証されること

- [ ] **Step 1: ci.yml に release-build ジョブを追加**

既存の `mix-review` ジョブと並列に実行する新ジョブ。`.github/workflows/ci.yml` を以下に置き換え:

```yaml
name: CI

on:
  push:
    branches:
      - main
    tags:
      - "v*"
  pull_request:

permissions:
  contents: read

concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  mix-review:
    name: mix review
    runs-on: ubuntu-24.04

    env:
      MIX_ENV: test

    steps:
      - name: Checkout
        uses: actions/checkout@v5

      - name: Set up Erlang/OTP and Elixir
        uses: erlef/setup-beam@v1
        with:
          otp-version: "28"
          elixir-version: "1.20"

      - name: Restore dependencies and build cache
        uses: actions/cache@v5
        with:
          path: |
            deps
            _build
          key: ${{ runner.os }}-mix-test-${{ hashFiles('mix.lock') }}
          restore-keys: |
            ${{ runner.os }}-mix-test-

      - name: Install dependencies
        run: mix deps.get

      - name: Run review gate
        run: mix review

  release-build:
    name: release build check
    runs-on: ubuntu-24.04

    env:
      MIX_ENV: prod

    steps:
      - name: Checkout
        uses: actions/checkout@v5

      - name: Set up Erlang/OTP and Elixir
        uses: erlef/setup-beam@v1
        with:
          otp-version: "28"
          elixir-version: "1.20"

      - name: Restore dependencies and build cache
        uses: actions/cache@v5
        with:
          path: |
            deps
            _build
          key: ${{ runner.os }}-mix-prod-${{ hashFiles('mix.lock') }}
          restore-keys: |
            ${{ runner.os }}-mix-prod-

      - name: Install dependencies
        run: mix deps.get --only prod

      - name: Compile
        run: mix compile

      - name: Deploy assets
        run: mix assets.deploy

      - name: Build release
        run: mix release
```

変更点:
- `on.push.tags` に `"v*"` を追加（タグ push でも CI が走る）
- 既存の cache key を `mix-test-` にリネーム（prod と衝突しないように）
- `release-build` ジョブを新規追加（`mix-review` と並列実行、依存関係なし）

- [ ] **Step 2: YAML の構文を検証**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" && echo "OK"
```

期待: `OK`

- [ ] **Step 3: コミット**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add release build verification job"
```

---

### Task 3: GitHub Releases ワークフロー

**Files:**
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: CI が `v*` タグで走ること（Task 2）
- Produces: `v*` タグ push で GitHub Release が自動作成されること

- [ ] **Step 1: release.yml を作成**

```yaml
name: Release

on:
  push:
    tags:
      - "v*"

permissions:
  contents: write

jobs:
  create-release:
    name: Create GitHub Release
    runs-on: ubuntu-24.04
    # CI が通ってからリリースを作成
    needs: []

    steps:
      - name: Checkout
        uses: actions/checkout@v5

      - name: Extract version from tag
        id: version
        run: echo "version=${GITHUB_REF_NAME#v}" >> "$GITHUB_OUTPUT"

      - name: Extract changelog
        id: changelog
        run: |
          # [未リリース] セクションの内容を抽出
          changelog=$(sed -n '/^## \[未リリース\]/,/^## \[/{/^## \[/!p}' CHANGELOG.md)
          {
            echo "body<<CHANGELOG_EOF"
            echo "$changelog"
            echo "CHANGELOG_EOF"
          } >> "$GITHUB_OUTPUT"

      - name: Create GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create "$GITHUB_REF_NAME" \
            --title "Ayumi $GITHUB_REF_NAME" \
            --notes "$(cat <<'NOTES_EOF'
          ${{ steps.changelog.outputs.body }}

          ---

          ## セットアップ手順

          事業所 PC (Windows) でのセットアップは [README の「本番デプロイ」セクション](https://github.com/SilentMalachite/Ayumi#本番デプロイwindows-事業所-pc) を参照してください。
          NOTES_EOF
          )"
```

- [ ] **Step 2: YAML の構文を検証**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" && echo "OK"
```

期待: `OK`

- [ ] **Step 3: コミット**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add GitHub Releases workflow on tag push"
```

---

### Task 4: Windows 向けセットアップ・起動スクリプト

**Files:**
- Create: `setup.bat` — 初回セットアップ用
- Create: `start.bat` — 起動用

**Interfaces:**
- Consumes: Task 1 の Mix release 設定
- Produces: 事業所 PC で `setup.bat` → `start.bat` でデプロイ・起動できること

- [ ] **Step 1: setup.bat を作成**

```bat
@echo off
chcp 65001 >nul
echo.
echo ========================================
echo   Ayumi セットアップ
echo ========================================
echo.

where elixir >nul 2>&1
if errorlevel 1 (
    echo [エラー] Elixir が見つかりません。
    echo https://elixir-lang.org/install.html からインストールしてください。
    pause
    exit /b 1
)

echo [1/5] 依存関係を取得しています...
set MIX_ENV=prod
call mix deps.get --only prod
if errorlevel 1 goto :error

echo [2/5] コンパイルしています...
call mix compile
if errorlevel 1 goto :error

echo [3/5] アセットをビルドしています...
call mix assets.deploy
if errorlevel 1 goto :error

echo [4/5] データベースを準備しています...
if not exist "data" mkdir data
set DATABASE_PATH=%~dp0data\ayumi.db
call mix ecto.create
call mix ecto.migrate
if errorlevel 1 goto :error

echo [5/5] リリースをビルドしています...
call mix release --overwrite
if errorlevel 1 goto :error

echo.
echo ========================================
echo   セットアップ完了
echo ========================================
echo.
echo 次のステップ:
echo   1. start.bat を編集して SECRET_KEY_BASE を設定してください
echo      (生成コマンド: mix phx.gen.secret)
echo   2. start.bat を実行してサーバを起動してください
echo.
pause
exit /b 0

:error
echo.
echo [エラー] セットアップに失敗しました。上記のエラーメッセージを確認してください。
pause
exit /b 1
```

- [ ] **Step 2: start.bat を作成**

```bat
@echo off
chcp 65001 >nul
echo.
echo Ayumi を起動しています...
echo.

rem --- ここを編集してください ---
rem SECRET_KEY_BASE は mix phx.gen.secret で生成できます（64文字以上）
set SECRET_KEY_BASE=CHANGE_ME_run_mix_phx_gen_secret_to_generate
rem ---------------------------------

if "%SECRET_KEY_BASE%"=="CHANGE_ME_run_mix_phx_gen_secret_to_generate" (
    echo [エラー] start.bat を編集して SECRET_KEY_BASE を設定してください。
    echo 生成コマンド: mix phx.gen.secret
    pause
    exit /b 1
)

set DATABASE_PATH=%~dp0data\ayumi.db
set PHX_SERVER=true
set PHX_HOST=localhost
set PORT=4000

echo サーバを起動します: http://localhost:%PORT%
echo LAN 上の他の端末からは http://（このPCのIPアドレス）:%PORT% でアクセスできます。
echo 停止するには Ctrl+C を押してください。
echo.

call _build\prod\rel\ayumi\bin\ayumi.bat start
```

- [ ] **Step 3: start.bat を .gitignore に追加**

`start.bat` には `SECRET_KEY_BASE` が書き込まれるため、テンプレートとして
`start.bat.example` をリポジトリに含め、実際の `start.bat` は .gitignore に追加する。

`start.bat` を `start.bat.example` にリネーム:

```bash
mv start.bat start.bat.example
```

`.gitignore` に追加:

```
# Secret key が書き込まれた起動スクリプト
/start.bat
```

- [ ] **Step 4: コミット**

```bash
git add setup.bat start.bat.example .gitignore
git commit -m "feat: add Windows setup and start scripts"
```

---

### Task 5: README にデプロイ手順を追加

**Files:**
- Modify: `README.md` — 本番デプロイセクション追加

**Interfaces:**
- Consumes: Task 1–4 の全成果物
- Produces: 事業所スタッフ（または設置担当者）がデプロイできるドキュメント

- [ ] **Step 1: README.md に本番デプロイセクションを追加**

「開発」セクションの直後、「ドメインモデル」セクションの前に以下を挿入:

```markdown
## 本番デプロイ（Windows 事業所 PC）

事業所の PC に Ayumi をデプロイする手順です。

### 前提条件

- **Windows 10/11** の事業所 PC
- **インターネット接続**（初回セットアップ時のみ。運用時は不要）
- **Erlang/OTP と Elixir** がインストール済み
  - [Elixir 公式サイト](https://elixir-lang.org/install.html) から Windows
    インストーラをダウンロードし、指示に従ってインストールしてください（Erlang/OTP も
    一緒にインストールされます）。

### 初回セットアップ

1. [GitHub Releases](https://github.com/SilentMalachite/Ayumi/releases) から
   最新バージョンの Source code (zip) をダウンロードし、任意のフォルダに展開します。

2. 展開したフォルダでコマンドプロンプトを開き、`setup.bat` を実行します:

   ```
   setup.bat
   ```

3. セットアップ完了後、`start.bat.example` を `start.bat` にコピーし、
   `SECRET_KEY_BASE` を設定します:

   ```
   copy start.bat.example start.bat
   ```

   `start.bat` をテキストエディタで開き、`SECRET_KEY_BASE=` の行を編集します。
   値はコマンドプロンプトで以下を実行して生成できます:

   ```
   mix phx.gen.secret
   ```

4. 職員アカウントを作成します:

   ```
   set MIX_ENV=prod
   set DATABASE_PATH=data\ayumi.db
   mix ayumi.create_user
   ```

### 起動

```
start.bat
```

ブラウザで `http://localhost:4000` を開きます。LAN 上の他の端末からは
`http://（この PC の IP アドレス）:4000` でアクセスできます。

### バージョンアップ

1. サーバを停止します（コマンドプロンプトで Ctrl+C）。
2. 新しいバージョンの Source code (zip) をダウンロードし、同じフォルダに上書き展開します。
3. `setup.bat` を再実行します（DB はそのまま引き継がれ、マイグレーションが適用されます）。
4. `start.bat` で起動します。

> **注意:** `start.bat` と `data/` フォルダ（DB ファイル）は上書きしないでください。
```

- [ ] **Step 2: コミット**

```bash
git add README.md
git commit -m "docs: add production deployment guide for Windows"
```

---

### Task 6: 最終検証 + `mix review`

**Files:**
- なし（検証のみ）

**Interfaces:**
- Consumes: Task 1–5 の全成果物
- Produces: 全テスト・品質ゲート通過の確認

- [ ] **Step 1: mix review を実行**

```bash
mix review
```

期待: format / compile / credo / test すべて PASS。

- [ ] **Step 2: リリースビルドを再検証**

```bash
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release --overwrite
```

期待: エラーなく完了。

- [ ] **Step 3: YAML ファイルの最終確認**

```bash
for f in .github/workflows/*.yml; do python3 -c "import yaml; yaml.safe_load(open('$f'))" && echo "$f: OK"; done
```

期待: 全ファイル OK。
