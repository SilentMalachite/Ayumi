defmodule AyumiWeb.SupportRecordLive.Index do
  use AyumiWeb, :live_view

  alias Ayumi.Plans
  alias Ayumi.Plans.SupportRecord
  alias Ayumi.Plans.SupportRecordCategory

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    service_users = Plans.list_service_users()

    socket =
      socket
      |> assign(:page_title, gettext("支援記録"))
      |> assign(:service_users, service_users)
      |> assign(:filter_service_user_id, nil)
      |> assign(:filter_from, today)
      |> assign(:filter_to, today)
      |> assign(:category_options, SupportRecordCategory.options())
      |> assign(:form, to_form(Plans.change_support_record(%SupportRecord{})))
      |> load_records()

    {:ok, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    service_user_id = parse_optional_id(params["service_user_id"])
    from = parse_date(params["from"])
    to = parse_date(params["to"])

    socket =
      socket
      |> assign(:filter_service_user_id, service_user_id)
      |> assign(:filter_from, from)
      |> assign(:filter_to, to)
      |> load_records()

    {:noreply, socket}
  end

  def handle_event("create", %{"support_record" => params}, socket) do
    scope = socket.assigns.current_scope

    case Plans.create_support_record(scope, params) do
      {:ok, _record} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("支援記録を保存しました"))
         |> assign(:form, to_form(Plans.change_support_record(%SupportRecord{})))
         |> load_records()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp load_records(socket) do
    opts =
      []
      |> then(fn o ->
        if socket.assigns.filter_service_user_id,
          do: Keyword.put(o, :service_user_id, socket.assigns.filter_service_user_id),
          else: o
      end)
      |> then(fn o ->
        if socket.assigns.filter_from,
          do: Keyword.put(o, :from, socket.assigns.filter_from),
          else: o
      end)
      |> then(fn o ->
        if socket.assigns.filter_to,
          do: Keyword.put(o, :to, socket.assigns.filter_to),
          else: o
      end)

    assign(socket, :records, Plans.list_support_records(socket.assigns.current_scope, opts))
  end

  defp parse_optional_id(""), do: nil
  defp parse_optional_id(nil), do: nil

  defp parse_optional_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {gettext("支援記録")}
      </.header>

      <form phx-change="filter" class="mt-6 flex flex-wrap gap-4 items-end">
        <div>
          <label class="block text-sm font-semibold text-zinc-800">{gettext("利用者")}</label>
          <select
            name="service_user_id"
            class="mt-1 block w-full rounded-md border border-zinc-300 bg-white shadow-sm focus:border-zinc-400 focus:ring-0 sm:text-sm"
          >
            <option value="">{gettext("全員")}</option>
            <option
              :for={su <- @service_users}
              value={su.id}
              selected={@filter_service_user_id == su.id}
            >
              {su.name}
            </option>
          </select>
        </div>
        <div>
          <label class="block text-sm font-semibold text-zinc-800">{gettext("開始日")}</label>
          <input
            type="date"
            name="from"
            value={@filter_from}
            class="mt-1 block rounded-md border border-zinc-300 bg-white shadow-sm focus:border-zinc-400 focus:ring-0 sm:text-sm"
          />
        </div>
        <div>
          <label class="block text-sm font-semibold text-zinc-800">{gettext("終了日")}</label>
          <input
            type="date"
            name="to"
            value={@filter_to}
            class="mt-1 block rounded-md border border-zinc-300 bg-white shadow-sm focus:border-zinc-400 focus:ring-0 sm:text-sm"
          />
        </div>
      </form>

      <.table id="support-records" rows={@records}>
        <:col :let={record} label={gettext("日時")}>
          {Calendar.strftime(record.recorded_at, "%Y-%m-%d %H:%M")}
        </:col>
        <:col :let={record} label={gettext("利用者")}>
          {record.service_user.name}
        </:col>
        <:col :let={record} label={gettext("区分")}>
          {SupportRecordCategory.label(record.category)}
        </:col>
        <:col :let={record} label={gettext("記入者")}>
          {record.recorded_by.email}
        </:col>
        <:col :let={record} label={gettext("内容")}>
          {record.content}
        </:col>
      </.table>

      <div class="mt-10">
        <h2 class="text-lg font-semibold text-zinc-800">{gettext("新規記録")}</h2>
        <.form for={@form} phx-submit="create" class="mt-4">
          <.input
            field={@form[:service_user_id]}
            type="select"
            label={gettext("利用者")}
            options={Enum.map(@service_users, &{&1.name, &1.id})}
            prompt={gettext("選択してください")}
          />
          <.input
            field={@form[:category]}
            type="select"
            label={gettext("区分")}
            options={@category_options}
            prompt={gettext("選択してください")}
          />
          <.input
            field={@form[:content]}
            type="textarea"
            label={gettext("内容")}
          />
          <div class="mt-4">
            <.button>{gettext("記録する")}</.button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
