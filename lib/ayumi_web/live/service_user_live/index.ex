defmodule AyumiWeb.ServiceUserLive.Index do
  use AyumiWeb, :live_view

  alias Ayumi.Plans
  alias Ayumi.Plans.ServiceUser

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "利用者一覧")
     |> assign(:form, to_form(Plans.change_service_user(%ServiceUser{})))
     |> assign(:service_users, Plans.list_service_users())}
  end

  @impl true
  def handle_event("save", %{"service_user" => params}, socket) do
    case Plans.create_service_user(params) do
      {:ok, _service_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "利用者を登録しました")
         |> assign(:form, to_form(Plans.change_service_user(%ServiceUser{})))
         |> assign(:service_users, Plans.list_service_users())}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>利用者一覧</.header>

      <.form
        for={@form}
        id="service-user-form"
        phx-submit="save"
        class="my-6 flex gap-2 items-end"
      >
        <.input field={@form[:name]} type="text" label="氏名" />
        <.input field={@form[:name_kana]} type="text" label="ふりがな" />
        <.button>登録</.button>
      </.form>

      <.table id="service-users" rows={@service_users}>
        <:col :let={su} label="氏名">
          <.link navigate={~p"/service_users/#{su.id}"}>{su.name}</.link>
        </:col>
        <:col :let={su} label="ふりがな">{su.name_kana}</:col>
      </.table>
    </Layouts.app>
    """
  end
end
