defmodule AyumiWeb.ExportController do
  @moduledoc """
  Serves CSV exports as file downloads. A plain controller because a LiveView
  cannot send a file; all the work happens in `Ayumi.Exports`.
  """
  use AyumiWeb, :controller

  alias Ayumi.Exports

  def download(conn, params) do
    case Exports.build(conn.assigns.current_scope, params) do
      {:ok, %{filename: filename, content: content}} ->
        send_download(conn, {:binary, content},
          filename: filename,
          content_type: "text/csv",
          charset: "utf-8"
        )

      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_flash(:error, gettext("出力条件が正しくありません。もう一度指定してください。"))
        |> redirect(to: ~p"/exports")
    end
  end
end
