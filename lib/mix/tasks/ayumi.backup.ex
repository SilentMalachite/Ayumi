defmodule Mix.Tasks.Ayumi.Backup do
  @shortdoc "Creates a SQLite backup via VACUUM INTO"
  @moduledoc """
  Creates a consistent backup of the Ayumi SQLite database.

      mix ayumi.backup PATH

  PATH is the directory where the backup file will be saved.
  The filename is generated automatically with a timestamp.

  ## Examples

      mix ayumi.backup /var/backups/ayumi
      mix ayumi.backup ./backups

  """
  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run([dest_dir]) do
    case Ayumi.Backups.create_backup(dest_dir) do
      {:ok, info} ->
        size_kb = div(info.size_bytes, 1024)

        Mix.shell().info("""
        バックアップが完了しました。
          パス: #{info.path}
          サイズ: #{size_kb} KB
        """)

      {:error, reason} ->
        Mix.shell().error("バックアップに失敗しました: #{reason}")
        exit({:shutdown, 1})
    end
  end

  def run(_) do
    Mix.shell().error("使い方: mix ayumi.backup <保存先ディレクトリ>")
    exit({:shutdown, 1})
  end
end
