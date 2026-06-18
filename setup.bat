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
echo   1. start.bat.example を start.bat にコピーしてください
echo   2. start.bat を編集して SECRET_KEY_BASE を設定してください
echo      (生成コマンド: mix phx.gen.secret)
echo   3. start.bat を実行してサーバを起動してください
echo.
pause
exit /b 0

:error
echo.
echo [エラー] セットアップに失敗しました。上記のエラーメッセージを確認してください。
pause
exit /b 1
