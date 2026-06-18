#!/bin/sh
set -e

echo ""
echo "========================================"
echo "  Ayumi セットアップ"
echo "========================================"
echo ""

if ! command -v elixir >/dev/null 2>&1; then
    echo "[エラー] Elixir が見つかりません。"
    echo "https://elixir-lang.org/install.html からインストールしてください。"
    exit 1
fi

echo "[1/5] 依存関係を取得しています..."
MIX_ENV=prod mix deps.get --only prod

echo "[2/5] コンパイルしています..."
MIX_ENV=prod mix compile

echo "[3/5] アセットをビルドしています..."
MIX_ENV=prod mix assets.deploy

echo "[4/5] データベースを準備しています..."
mkdir -p data
DATABASE_PATH="$(cd "$(dirname "$0")" && pwd)/data/ayumi.db"
export DATABASE_PATH
MIX_ENV=prod mix ecto.create
MIX_ENV=prod mix ecto.migrate

echo "[5/5] リリースをビルドしています..."
MIX_ENV=prod mix release --overwrite

echo ""
echo "========================================"
echo "  セットアップ完了"
echo "========================================"
echo ""
echo "次のステップ:"
echo "  1. start.sh.example を start.sh にコピーしてください"
echo "     cp start.sh.example start.sh"
echo "  2. start.sh を編集して SECRET_KEY_BASE を設定してください"
echo "     (生成コマンド: mix phx.gen.secret)"
echo "  3. start.sh を実行してサーバを起動してください"
echo "     ./start.sh"
echo ""
