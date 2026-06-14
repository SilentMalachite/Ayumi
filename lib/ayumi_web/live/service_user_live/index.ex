defmodule AyumiWeb.ServiceUserLive.Index do
  use AyumiWeb, :live_view

  alias Ayumi.Plans

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("利用者一覧"))
     |> assign(:service_users, Plans.list_service_users())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {gettext("利用者一覧")}
        <:actions>
          <.button navigate={~p"/service_users/new"}>{gettext("新規登録")}</.button>
        </:actions>
      </.header>

      <.table id="service-users" rows={@service_users}>
        <:col :let={su} label={gettext("氏名")}>
          <.link navigate={~p"/service_users/#{su.id}"}>{su.name}</.link>
        </:col>
        <:col :let={su} label={gettext("ふりがな")}>{su.name_kana}</:col>
        <:col :let={su} label={gettext("受給者証番号")}>{su.recipient_cert_number}</:col>
      </.table>
    </Layouts.app>
    """
  end
end
