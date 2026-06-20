defmodule Ayumi.Backups do
  @moduledoc false

  alias Ayumi.Repo

  @doc """
  Creates a consistent SQLite backup using VACUUM INTO.

  Returns `{:ok, info}` with the backup path, size, and timestamp,
  or `{:error, reason}` on failure.
  """
  def create_backup(dest_dir, opts \\ []) do
    with :ok <- validate_directory(dest_dir),
         :ok <- validate_not_self(dest_dir),
         {:ok, dest_path} <- vacuum_into_unique_path(dest_dir, opts),
         {:ok, stat} <- stat_backup(dest_path) do
      {:ok, %{path: dest_path, size_bytes: stat.size, created_at: DateTime.utc_now()}}
    end
  end

  defp validate_directory(dir) do
    cond do
      not File.dir?(dir) ->
        {:error, "指定されたディレクトリが存在しない: #{dir}"}

      not writable?(dir) ->
        {:error, "ディレクトリに書き込み権限がありません: #{dir}"}

      true ->
        :ok
    end
  end

  defp writable?(dir) do
    probe = Path.join(dir, ".ayumi_write_probe_#{System.unique_integer([:positive])}")

    case File.touch(probe) do
      :ok ->
        File.rm(probe)
        true

      {:error, _} ->
        false
    end
  end

  defp validate_not_self(dest_dir) do
    db_path = Repo.config()[:database] |> Path.expand() |> Path.dirname()
    dest_abs = Path.expand(dest_dir)

    if dest_abs == db_path do
      {:error, "バックアップ先が稼働中DBと同じディレクトリです。別のディレクトリを指定してください"}
    else
      :ok
    end
  end

  @max_collision_retries 16

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
      try_vacuum_into(dir, base, count, path)
    end
  end

  defp try_vacuum_into(dir, base, count, path) do
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

  defp execute_vacuum_into(dest_path) do
    # VACUUM INTO cannot run inside a transaction, so we open a direct
    # Exqlite connection to the source DB file rather than going through
    # Ecto's connection pool (which wraps queries in a transaction in test mode).
    db_path = Repo.config()[:database] |> Path.expand()
    safe_dest = String.replace(dest_path, "'", "''")
    sql = "VACUUM INTO '#{safe_dest}'"

    case Exqlite.Sqlite3.open(db_path) do
      {:ok, conn} ->
        result = Exqlite.Sqlite3.execute(conn, sql)
        Exqlite.Sqlite3.close(conn)

        case result do
          :ok -> :ok
          {:error, err} -> {:error, "VACUUM INTO failed: #{inspect(err)}"}
        end

      {:error, err} ->
        {:error, "Failed to open database for backup: #{inspect(err)}"}
    end
  end

  defp stat_backup(path) do
    case File.stat(path) do
      {:ok, stat} -> {:ok, stat}
      {:error, reason} -> {:error, "バックアップファイルの確認に失敗しました: #{reason}"}
    end
  end
end
