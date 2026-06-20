defmodule Ayumi.BackupsTest do
  use Ayumi.DataCase, async: false

  alias Ayumi.Backups

  describe "create_backup/2" do
    test "returns error for non-existent directory" do
      assert {:error, reason} =
               Backups.create_backup("/tmp/ayumi_no_such_dir_#{System.unique_integer()}")

      assert reason =~ "存在しない" or reason =~ "not found" or reason =~ "does not exist"
    end

    @tag :tmp_dir
    test "creates a valid backup file in the target directory", %{tmp_dir: tmp_dir} do
      assert {:ok, info} = Backups.create_backup(tmp_dir)
      assert File.exists?(info.path)
      assert info.size_bytes > 0
      assert String.starts_with?(Path.basename(info.path), "ayumi_backup_")
      assert String.ends_with?(info.path, ".sqlite3")

      # Verify the backup is a readable SQLite database with expected tables
      {:ok, conn} = Exqlite.Sqlite3.open(info.path)

      {:ok, stmt} =
        Exqlite.Sqlite3.prepare(
          conn,
          "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        )

      tables = collect_rows(stmt, conn)
      Exqlite.Sqlite3.close(conn)

      assert "users" in tables
      assert "support_plans" in tables
    end

    test "returns error when dest_dir is the same as the running DB directory" do
      db_dir = Ayumi.Repo.config()[:database] |> Path.expand() |> Path.dirname()
      assert {:error, reason} = Backups.create_backup(db_dir)
      assert reason =~ "同じディレクトリ"
    end

    @tag :tmp_dir
    test "同じ秒のタイムスタンプでも2回目はサフィックスで衝突を避ける", %{tmp_dir: tmp_dir} do
      ts = ~N[2026-06-20 12:00:00]

      assert {:ok, info1} = Backups.create_backup(tmp_dir, timestamp: ts)
      assert {:ok, info2} = Backups.create_backup(tmp_dir, timestamp: ts)

      assert info1.path != info2.path
      assert File.exists?(info1.path)
      assert File.exists?(info2.path)
      assert String.ends_with?(info2.path, "_1.sqlite3")
    end

    @tag :tmp_dir
    test "衝突候補が上限を超えたらエラーで諦める", %{tmp_dir: tmp_dir} do
      ts = ~N[2026-06-20 12:00:00]
      base = "ayumi_backup_20260620_120000"

      File.touch!(Path.join(tmp_dir, base <> ".sqlite3"))

      for i <- 1..16 do
        File.touch!(Path.join(tmp_dir, "#{base}_#{i}.sqlite3"))
      end

      assert {:error, reason} = Backups.create_backup(tmp_dir, timestamp: ts)
      assert reason =~ "衝突"
    end

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
  end

  defp collect_rows(stmt, conn, acc \\ []) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [value]} -> collect_rows(stmt, conn, [value | acc])
      :done -> Enum.reverse(acc)
    end
  end
end
