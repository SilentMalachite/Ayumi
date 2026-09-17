defmodule AyumiWeb.ExportLive.Index do
  use AyumiWeb, :live_view

  alias Ayumi.Exports
  alias Ayumi.Exports.Dataset
  alias Ayumi.Exports.Period
  alias Ayumi.Plans

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("CSV出力"))
     |> assign(:dataset_options, Dataset.options())
     |> assign(:unit_options, Period.unit_options())
     |> assign(:service_users, Plans.list_service_users(include_withdrawn: true))
     |> assign_request(Exports.change_request())}
  end

  @impl true
  def handle_event("change", %{"export" => params}, socket) do
    {:noreply, assign_request(socket, Exports.change_request(params))}
  end

  defp assign_request(socket, changeset) do
    socket
    |> assign(:form, to_form(changeset, as: :export))
    |> assign(:period_label, Exports.period_label(changeset))
    |> assign(:download_params, Exports.request_params(changeset))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {gettext("CSV出力")}
        <:subtitle>
          {gettext("記録を Excel で開ける CSV ファイルとして保存します。")}
        </:subtitle>
      </.header>

      <.form for={@form} id="export-form" phx-change="change" class="mt-6">
        <.input
          field={@form[:dataset]}
          type="select"
          label={gettext("出力するデータ")}
          options={@dataset_options}
        />
        <.input
          field={@form[:unit]}
          type="select"
          label={gettext("期間の単位")}
          options={@unit_options}
        />
        <.input field={@form[:anchor_date]} type="date" label={gettext("基準日")} />
        <p class="text-sm text-base-content/60">
          {gettext("基準日を含む週(月曜始まり)・月・年度(4月〜翌3月)・暦年が出力されます。")}
        </p>
        <.input
          field={@form[:service_user_id]}
          type="select"
          label={gettext("利用者")}
          options={Enum.map(@service_users, &{&1.name, &1.id})}
          prompt={gettext("全員")}
        />
      </.form>

      <div :if={@download_params} class="mt-6 space-y-4">
        <p id="export-period">
          {gettext("出力期間")}: <strong>{@period_label}</strong>
        </p>
        <.button
          id="export-download"
          href={~p"/exports/download?#{@download_params}"}
          download
          variant="primary"
        >
          {gettext("CSVをダウンロード")}
        </.button>
      </div>

      <p class="mt-8 text-sm text-base-content/60">
        {gettext("CSV には個人情報が含まれます。保存先と持ち出しに注意してください。")}
      </p>
    </Layouts.app>
    """
  end
end
