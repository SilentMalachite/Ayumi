# DBバックアップ ファイル名衝突レース修正 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Ayumi.Backups.create_backup/2` の「空き名選定 → VACUUM INTO」を1ステップに統合し、同一秒の並行実行でも全件 `{:ok, _}` で衝突なくバックアップを生成できるようにする。

**Architecture:** 既存の `build_dest_path/2` と `available_path/3` を破棄し、選定と VACUUM 実行を1つの再帰関数 `vacuum_attempt/3` に統合する。各試行は「候補パスが既存なら即次へ」「未存在なら VACUUM を試す」「VACUUM 失敗かつ出力先が存在するなら他プロセスが先取りしたと判定して次サフィックスへ」「ファイルが無い失敗（権限・ディスク等）はそのまま返す」という方針。エラーメッセージ文字列ではなくファイル存在で判定するため、Exqlite 側のメッセージ変動に強い。

**Tech Stack:** Elixir / Phoenix / `ecto_sqlite3` (SQLite, WAL) / `Exqlite.Sqlite3` 直接接続 / ExUnit (`async: false`, `:tmp_dir` tag) / `Task.async_stream`。

## Global Constraints

- 触ってよいファイルは2つだけ: `test/ayumi/backups_test.exs`（並行テスト追加）と `lib/ayumi/backups.ex`（`create_backup/2` の `with` 1行＋選定関数置換）。
- `execute_vacuum_into/1` の接続・SQL 組み立ては変更しない。
- `@max_collision_retries` は `16` のまま据え置く。
- ファイル名体系 `ayumi_backup_YYYYMMDD_HHMMSS[_n].sqlite3` は変えない。
- `validate_directory/1` `validate_not_self/1` `writable?/1` `stat_backup/1` は変更しない。
- 失敗時のリトライ判定は VACUUM のエラーメッセージ文字列ではなく **出力先ファイルの存在** で行う。
- 連続実行用の既存テスト `"同じ秒のタイムスタンプでも2回目はサフィックスで衝突を避ける"` と `"衝突候補が上限を超えたらエラーで諦める"` はそのままグリーン維持（連続パスの回帰防止）。
- 最小差分。ついでのリファクタ・整形を一切しない。
- 完了は `mix review`（format / compile --warnings-as-errors / credo / test）グリーンで判定。
- 応答・コミットメッセージともに日本語可。コード識別子は英語、コメントは英語。
- このプロジェクトは SQLite ファイルを単一プロセスが所有するモデル。並行は **同一 BEAM ノード内の OS プロセス間** ではなく **同一 BEAM 内の複数 Elixir プロセス** が対象（テストも `Task.async_stream`）。

---

## File Structure

- `lib/ayumi/backups.ex` — 既存 `create_backup/2` の `with` を1行差し替え、`build_dest_path/2` と `available_path/3` を削除して `vacuum_into_unique_path/2` と `vacuum_attempt/3` を追加する。それ以外の関数は不変。
- `test/ayumi/backups_test.exs` — `describe "create_backup/2"` の末尾に並行テストを1件追加する。既存テストは触らない。

---

## Task 1: 並行レースを再現する失敗テストを書く (Red)

**Files:**
- Modify: `test/ayumi/backups_test.exs`（`describe "create_backup/2"` の `do` ブロック末尾、上限テストの直後に1件追加）
- Test: `test/ayumi/backups_test.exs`

**Interfaces:**
- Consumes: `Ayumi.Backups.create_backup/2` の既存シグネチャ `create_backup(dest_dir :: String.t(), opts :: keyword()) :: {:ok, %{path: String.t(), size_bytes: pos_integer(), created_at: DateTime.t()}} | {:error, String.t()}`。
- Produces: 並行実行で全件成功＋全パス一意＋全ファイル存在を保証する回帰テスト。Task 2 はこのテストを通すために実装する。

- [ ] **Step 1: 失敗テストを `test/ayumi/backups_test.exs` の `describe "create_backup/2"` 末尾、`"衝突候補が上限を超えたらエラーで諦める"` テストの直後に追加する**

挿入位置は既存の `衝突候補が上限を超えたらエラーで諦める` テストの `end` の直後、`describe` ブロックを閉じる `end` の前。追加するコードは以下：

```elixir
    @tag :tmp_dir
    test "同じ秒に並列実行しても全件成功し、パスが衝突しない", %{tmp_dir: tmp_dir} do
      ts = ~N[2026-06-20 12:00:00]
      concurrency = 4

      results =
        1..concurrency
        |> Task.async_stream(
          fn _ -> Backups.create_backup(tmp_dir, timestamp: ts) end,
          max_concurrency: concurrency,
          timeout: 30_000
        )
        |> Enum.map(fn {:ok, res} -> res end)

      assert Enum.all?(results, &match?({:ok, _}, &1)),
             "一部のバックアップが失敗しました: #{inspect(results)}"

      paths = for {:ok, info} <- results, do: info.path
      assert length(paths) == concurrency
      assert length(Enum.uniq(paths)) == concurrency
      assert Enum.all?(paths, &File.exists?/1)
    end
```

注意事項:
- `Task.async_stream` の `{:ok, res}` パターンは「タスク自体は完了」を意味し、その中身 `res` が `{:ok, info}` か `{:error, reason}`。`match?({:ok, _}, &1)` で `res` のレベルの成功を判定している（このネストを混同しないこと）。
- `execute_vacuum_into/1` は Ecto 接続プールを経由せず Exqlite 直接接続のため、`Task.async_stream` の子プロセスに Ecto sandbox 許可を渡す必要はない。
- ファイル `use Ayumi.DataCase, async: false` のままで OK（このモジュールは元々 `async: false`）。

- [ ] **Step 2: テストを実行し、新規追加分が落ちることを確認する**

Run: `mix test test/ayumi/backups_test.exs --only line:<新規テストの行番号>`
（行番号が面倒なら `mix test test/ayumi/backups_test.exs` 全部でも可）

Expected: 新規テストが **失敗する**。典型的には4プロセスのうち1件のみが `{:ok, _}` で、残りが `{:error, "VACUUM INTO failed: ..."}`（`table "schema_migrations" already exists` 等のメッセージ）になり、`assert Enum.all?(results, &match?({:ok, _}, &1))` で停止する。既存4テストは引き続きグリーン。

落ちなかった場合は実装が既に直っているか、`@tag :tmp_dir` の付け忘れ／インデント不一致が疑われるので、テスト配置を見直す。

- [ ] **Step 3: 一時コミットせず、そのまま Task 2 に進む**

Red のまま Task 2 で Green にするので、ここではコミットしない。`git status` でテストファイル1件のみ変更されていることを確認する。

Run: `git status --short test/ayumi/backups_test.exs`
Expected: ` M test/ayumi/backups_test.exs`

---

## Task 2: 選定と VACUUM を1つのリトライループに統合する (Green)

**Files:**
- Modify: `lib/ayumi/backups.ex`（`create_backup/2` の `with` 1行差し替え、`build_dest_path/2`＋`available_path/3` を `vacuum_into_unique_path/2`＋`vacuum_attempt/3` に置換）

**Interfaces:**
- Consumes: `validate_directory/1`, `validate_not_self/1`, `execute_vacuum_into/1`, `stat_backup/1`, `@max_collision_retries`（既存・不変）。
- Produces: 新規 private 関数
  - `vacuum_into_unique_path(dest_dir :: String.t(), opts :: keyword()) :: {:ok, String.t()} | {:error, String.t()}` — `dest_dir` 配下に一意な `.sqlite3` パスを決めて VACUUM INTO まで完了したら `{:ok, path}` を返す。
  - `vacuum_attempt(dir :: String.t(), base :: String.t(), count :: non_neg_integer()) :: {:ok, String.t()} | {:error, String.t()}` — 候補パスを生成し、既存なら次へ、未存在なら VACUUM、VACUUM 失敗時はファイル存在で次へか中断かを判定する再帰関数。
- 削除: `build_dest_path/2`, `available_path/3`。

- [ ] **Step 1: `create_backup/2` の `with` を差し替える**

`lib/ayumi/backups.ex` の `create_backup/2` 内、

```elixir
         {:ok, dest_path} <- build_dest_path(dest_dir, opts),
         :ok <- execute_vacuum_into(dest_path),
```

を、以下の1行に置換する：

```elixir
         {:ok, dest_path} <- vacuum_into_unique_path(dest_dir, opts),
```

差し替え後の `create_backup/2` 全体は次のとおり：

```elixir
  def create_backup(dest_dir, opts \\ []) do
    with :ok <- validate_directory(dest_dir),
         :ok <- validate_not_self(dest_dir),
         {:ok, dest_path} <- vacuum_into_unique_path(dest_dir, opts),
         {:ok, stat} <- stat_backup(dest_path) do
      {:ok, %{path: dest_path, size_bytes: stat.size, created_at: DateTime.utc_now()}}
    end
  end
```

- [ ] **Step 2: `build_dest_path/2` と `available_path/3` を `vacuum_into_unique_path/2` と `vacuum_attempt/3` に置換する**

`lib/ayumi/backups.ex` の以下のブロック（`@max_collision_retries 16` の直下）

```elixir
  defp build_dest_path(dest_dir, opts) do
    now = Keyword.get(opts, :timestamp, NaiveDateTime.utc_now())
    base = "ayumi_backup_" <> Calendar.strftime(now, "%Y%m%d_%H%M%S")
    available_path(dest_dir, base, 0)
  end

  defp available_path(_dir, base, count) when count > @max_collision_retries do
    {:error, "バックアップファイル名の衝突回避に失敗しました: #{base}"}
  end

  defp available_path(dir, base, count) do
    suffix = if count == 0, do: "", else: "_#{count}"
    path = Path.join(dir, base <> suffix <> ".sqlite3")

    if File.exists?(path) do
      available_path(dir, base, count + 1)
    else
      {:ok, path}
    end
  end
```

を、次のブロックに置き換える：

```elixir
  defp vacuum_into_unique_path(dest_dir, opts) do
    now = Keyword.get(opts, :timestamp, NaiveDateTime.utc_now())
    base = "ayumi_backup_" <> Calendar.strftime(now, "%Y%m%d_%H%M%S")
    vacuum_attempt(dest_dir, base, 0)
  end

  defp vacuum_attempt(_dir, base, count) when count > @max_collision_retries do
    {:error, "バックアップファイル名の衝突回避に失敗しました: #{base}"}
  end

  defp vacuum_attempt(dir, base, count) do
    suffix = if count == 0, do: "", else: "_#{count}"
    path = Path.join(dir, base <> suffix <> ".sqlite3")

    if File.exists?(path) do
      # 既存名は VACUUM を試さず次へ（連続実行の高速パス）
      vacuum_attempt(dir, base, count + 1)
    else
      case execute_vacuum_into(path) do
        :ok ->
          {:ok, path}

        {:error, reason} ->
          # 出力先が存在する＝並行実行で他プロセスが先に作成 → 次サフィックスへ。
          # ファイルが無い失敗（権限・ディスク等）はそのまま返す。
          if File.exists?(path),
            do: vacuum_attempt(dir, base, count + 1),
            else: {:error, reason}
      end
    end
  end
```

重要:
- `@max_collision_retries 16` の宣言行はそのまま残す（このブロックの直前にある）。
- 関数の引数順序 `(dir, base, count)` は元の `available_path/3` と同一に保つ（差分最小化）。
- ガード `when count > @max_collision_retries` も元の閾値そのまま。
- コメント2行は方針が読み取りにくいので追加する（要点が短く非自明なため）。

- [ ] **Step 3: 単体実行で Red→Green を確認する**

Run: `mix test test/ayumi/backups_test.exs`
Expected: **5 tests, 0 failures**。新規の並行テスト含めすべてグリーン。

落ちた場合のチェックポイント:
- 並行テストだけ落ち続ける → `vacuum_attempt` の VACUUM 失敗ブランチで `File.exists?(path)` を判定しているか、`do:` / `else:` の対応が逆になっていないかを確認。
- 上限テストが落ちる → ガード `count > @max_collision_retries` のままで、`>=` になっていないかを確認（元仕様は16連続全埋め＋本命1の計17ファイルでエラー）。
- 連続実行テストが落ちる → 既存ファイルがあるとき VACUUM をスキップして次へ進む高速パス（`if File.exists?(path) do vacuum_attempt(...)` の分岐）が消えていないかを確認。

- [ ] **Step 4: 関連 LiveView テストの巻き添えチェック**

Run: `mix test test/ayumi_web/live/admin/backup_live_test.exs`
Expected: 既存通り **すべてグリーン**（このタスクは公開 API のシグネチャを変えていないため、LiveView 側は無風のはず）。

落ちた場合は `create_backup/2` の戻り値形 `%{path: ..., size_bytes: ..., created_at: ...}` を壊していないか確認。

- [ ] **Step 5: 中間コミット**

```bash
git add lib/ayumi/backups.ex test/ayumi/backups_test.exs
git commit -m "fix: backup ファイル名衝突を並行実行でも回避する

VACUUM 失敗かつ出力先が存在するときのみ次サフィックスへリトライする方針で、
選定と VACUUM INTO を vacuum_attempt/3 に統合した。同一秒の4並列でも全件成功
することを Task.async_stream のテストで担保する。"
```

---

## Task 3: 品質ゲート (`mix review`) と完了報告

**Files:**
- 変更なし。`mix review` を実行し、必要に応じてフォーマット差分だけ拾う。

**Interfaces:**
- Consumes: Task 1〜2 で確定したテストと実装。
- Produces: グリーンの `mix review` 末尾出力。完了報告に添付する。

- [ ] **Step 1: `mix review` を実行する**

Run: `mix review`
Expected: format / compile --warnings-as-errors / credo / test がすべてグリーン。

`mix review` が無い場合は `mix format --check-formatted && mix compile --warnings-as-errors && mix credo --strict && mix test` を順に実行して同等の確認をする。

- [ ] **Step 2: もし `mix format --check-formatted` が落ちていたら、当該ファイルのみフォーマットして追コミット**

```bash
mix format lib/ayumi/backups.ex test/ayumi/backups_test.exs
git add lib/ayumi/backups.ex test/ayumi/backups_test.exs
git commit -m "chore: format backups race fix"
```

ただし、フォーマッタが触ったのが追加分のインデントだけであることを `git diff HEAD~1` で確認する（最小差分原則）。

- [ ] **Step 3: 差分を §1 の2ファイルに限定できているか最終確認**

Run: `git diff --name-only main...HEAD`
Expected:
```
lib/ayumi/backups.ex
test/ayumi/backups_test.exs
```

それ以外のファイルが出てきたら、関係ない変更を `git restore --staged` & `git checkout --` で巻き戻す（ただし破壊操作の前に必ず内容確認）。

- [ ] **Step 4: 受け入れ条件チェックリストを目視で確認**

- [ ] 並行テスト：4並列・同一秒で全件 `{:ok, _}`、パス4件が一意、全ファイル存在 → Task 2 Step 3 で確認済
- [ ] 既存「同一秒の連続実行」テスト グリーン維持 → Task 2 Step 3 で確認済
- [ ] 既存 backups / backup_live テスト グリーン維持 → Task 2 Step 3/4 で確認済
- [ ] `mix review` グリーン → Task 3 Step 1 で確認済
- [ ] 差分は §1 の2ファイルのみ → Task 3 Step 3 で確認済

- [ ] **Step 5: 完了報告を書く**

以下のフォーマットで返す:

1. 変更ファイルと概算 ±行数（`git diff --stat main...HEAD` の出力を貼る）
2. 追加テストの要旨（4並列・同一秒で衝突しないこと）
3. `mix review` 末尾出力（グリーンの証跡）

---

## やらないこと（スコープ厳守の念押し）

- リトライ判定を VACUUM の **エラーメッセージ文字列** で行わない。出力先の存在で判定する。
- `@max_collision_retries` の値を変えない。
- `execute_vacuum_into/1` の接続・SQL 組み立てには手を入れない。
- ファイル名体系 `ayumi_backup_YYYYMMDD_HHMMSS[_n].sqlite3` を変えない。
- ついでのリファクタ・整形をしない。最小差分。
- 既存テスト「同じ秒のタイムスタンプでも2回目はサフィックスで衝突を避ける」「衝突候補が上限を超えたらエラーで諦める」は **触らない**（連続パスと上限の回帰用に残す）。
- LiveView やバックアップ Mix タスク (`mix ayumi.backup`) の挙動・引数を変えない。
