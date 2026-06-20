defmodule AyumiWeb.BackupLive.Index do
  use AyumiWeb, :live_view

  alias Ayumi.Backups

  @impl true
  def mount(_params, _session, socket) do
    default_dir = Application.get_env(:ayumi, :backup_dir, "")

    {:ok,
     socket
     |> assign(:page_title, gettext("データベースバックアップ"))
     |> assign(:dest_dir, default_dir)
     |> assign(:result, nil)}
  end

  @impl true
  def handle_event("backup", %{"dest_dir" => dest_dir}, socket) do
    case Backups.create_backup(dest_dir) do
      {:ok, info} ->
        size_kb = div(info.size_bytes, 1024)

        {:noreply,
         socket
         |> assign(:result, {:ok, info})
         |> put_flash(
           :info,
           gettext("バックアップが完了しました: %{path} (%{size} KB)",
             path: info.path,
             size: size_kb
           )
         )}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:result, {:error, reason})
         |> put_flash(
           :error,
           gettext("バックアップに失敗しました: %{reason}", reason: reason)
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {gettext("データベースバックアップ")}
    </.header>

    <div class="mt-6">
      <form id="backup-form" phx-submit="backup" class="space-y-4">
        <div>
          <label for="dest_dir" class="block text-sm font-medium">
            {gettext("保存先ディレクトリ")}
          </label>
          <input
            type="text"
            name="dest_dir"
            id="dest_dir"
            value={@dest_dir}
            class="input input-bordered w-full mt-1"
            placeholder="/path/to/backup/directory"
            required
          />
          <p class="mt-1 text-sm text-base-content/60">
            {gettext("バックアップファイルの保存先を指定してください。タイムスタンプ付きのファイル名が自動生成されます。")}
          </p>
        </div>

        <button type="submit" class="btn btn-primary">
          {gettext("バックアップ実行")}
        </button>
      </form>

      <div :if={match?({:ok, _}, @result)} class="mt-6 alert alert-success">
        <div>
          <p class="font-semibold">{gettext("バックアップ完了")}</p>
          <p class="text-sm">{elem(@result, 1).path}</p>
          <p class="text-sm">{div(elem(@result, 1).size_bytes, 1024)} KB</p>
        </div>
      </div>

      <div :if={match?({:error, _}, @result)} class="mt-6 alert alert-error">
        <div>
          <p class="font-semibold">{gettext("バックアップに失敗しました")}</p>
          <p class="text-sm">{elem(@result, 1)}</p>
        </div>
      </div>
    </div>
    """
  end
end
