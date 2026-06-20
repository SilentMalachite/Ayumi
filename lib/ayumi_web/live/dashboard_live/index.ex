defmodule AyumiWeb.DashboardLive.Index do
  use AyumiWeb, :live_view

  alias Ayumi.Accounts.User
  alias Ayumi.Plans

  @near_days 30
  @cert_near_days 60

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    today = Date.utc_today()

    monitoring_alerts =
      Plans.list_monitoring_deadline_alerts(scope, today, @near_days)

    certificate_alerts =
      Plans.list_certificate_expiry_alerts(scope, today, @cert_near_days)

    socket =
      socket
      |> assign(:page_title, gettext("ダッシュボード"))
      |> assign(:near_days, @near_days)
      |> assign(:cert_near_days, @cert_near_days)
      |> assign(:monitoring_alerts, monitoring_alerts)
      |> assign(:certificate_alerts, certificate_alerts)
      |> push_deadline_notification(monitoring_alerts)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {gettext("ダッシュボード")}
        <:subtitle>{gettext("モニタリング期限と担当状況を確認します")}</:subtitle>
      </.header>

      <section id="monitoring-alerts" phx-hook="DeadlineNotifier" class="space-y-3">
        <div class="flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <h2 class="text-base font-semibold text-zinc-900">{gettext("モニタリング期限")}</h2>
            <p class="text-sm text-zinc-600">
              {gettext("超過と%{days}日以内の予定を表示しています", days: @near_days)}
            </p>
          </div>
          <.link
            navigate={~p"/service_users"}
            class="text-sm font-semibold text-zinc-700 hover:text-zinc-950"
          >
            {gettext("利用者一覧へ")}
          </.link>
        </div>

        <div
          :if={@monitoring_alerts == []}
          id="monitoring-alerts-empty"
          class="rounded-lg border border-dashed border-zinc-300 bg-white px-4 py-5 text-sm text-zinc-600"
        >
          {gettext("期限が近いモニタリング予定はありません")}
        </div>

        <div
          :for={alert <- @monitoring_alerts}
          id={"monitoring-alert-#{alert.support_plan.id}"}
          class="rounded-lg border border-zinc-200 bg-white p-4 shadow-sm transition hover:shadow-md"
        >
          <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <div class="flex flex-wrap items-center gap-2">
                <span class={[
                  "rounded-full px-2 py-1 text-xs font-semibold",
                  alert.status == :overdue && "bg-red-100 text-red-800",
                  alert.status == :near && "bg-amber-100 text-amber-800"
                ]}>
                  {deadline_status_label(alert.status)}
                </span>
                <span
                  :if={alert.assigned_to_current_user?}
                  class="rounded-full bg-zinc-100 px-2 py-1 text-xs font-semibold text-zinc-700"
                >
                  {gettext("自分の担当")}
                </span>
              </div>

              <h3 class="mt-2 text-base font-semibold text-zinc-900">
                <.link navigate={~p"/service_users/#{alert.support_plan.service_user.id}"}>
                  {alert.support_plan.service_user.name}
                </.link>
              </h3>

              <p class="mt-1 text-sm text-zinc-600">
                {gettext("担当")}: {User.display_name(alert.support_plan.staff)}
              </p>
            </div>

            <div class="text-left sm:text-right">
              <p class="text-sm text-zinc-600">{gettext("次回モニタリング予定日")}</p>
              <p class="text-lg font-semibold text-zinc-900">
                {alert.support_plan.next_monitoring_date}
              </p>
              <p class="text-sm text-zinc-600">{days_until_label(alert.days_until)}</p>
            </div>
          </div>

          <div class="mt-3 flex flex-wrap gap-3 text-sm font-semibold">
            <.link
              navigate={~p"/support_plans/#{alert.support_plan.id}"}
              class="text-zinc-800 hover:text-zinc-950"
            >
              {gettext("計画を開く")}
            </.link>
            <.link
              navigate={~p"/service_users/#{alert.support_plan.service_user.id}"}
              class="text-zinc-600 hover:text-zinc-950"
            >
              {gettext("利用者詳細")}
            </.link>
          </div>
        </div>
      </section>

      <section id="certificate-alerts" class="mt-8 space-y-3">
        <div class="flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <h2 class="text-base font-semibold text-zinc-900">{gettext("受給者証期限")}</h2>
            <p class="text-sm text-zinc-600">
              {gettext("超過と%{days}日以内の期限を表示しています", days: @cert_near_days)}
            </p>
          </div>
          <.link
            navigate={~p"/service_users"}
            class="text-sm font-semibold text-zinc-700 hover:text-zinc-950"
          >
            {gettext("利用者一覧へ")}
          </.link>
        </div>

        <div
          :if={@certificate_alerts == []}
          id="certificate-alerts-empty"
          class="rounded-lg border border-dashed border-zinc-300 bg-white px-4 py-5 text-sm text-zinc-600"
        >
          {gettext("期限が近い受給者証はありません")}
        </div>

        <div
          :for={alert <- @certificate_alerts}
          id={"certificate-alert-#{alert.service_user.id}"}
          class="rounded-lg border border-zinc-200 bg-white p-4 shadow-sm transition hover:shadow-md"
        >
          <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <span class={[
                "rounded-full px-2 py-1 text-xs font-semibold",
                alert.status == :overdue && "bg-red-100 text-red-800",
                alert.status == :near && "bg-amber-100 text-amber-800"
              ]}>
                {deadline_status_label(alert.status)}
              </span>

              <h3 class="mt-2 text-base font-semibold text-zinc-900">
                <.link navigate={~p"/service_users/#{alert.service_user.id}"}>
                  {alert.service_user.name}
                </.link>
              </h3>
            </div>

            <div class="text-left sm:text-right">
              <p class="text-sm text-zinc-600">{gettext("受給者証有効期限")}</p>
              <p class="text-lg font-semibold text-zinc-900">
                {alert.service_user.recipient_cert_expiry}
              </p>
              <p class="text-sm text-zinc-600">{days_until_label(alert.days_until)}</p>
            </div>
          </div>

          <div class="mt-3 flex flex-wrap gap-3 text-sm font-semibold">
            <.link
              navigate={~p"/service_users/#{alert.service_user.id}"}
              class="text-zinc-600 hover:text-zinc-950"
            >
              {gettext("利用者詳細")}
            </.link>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp push_deadline_notification(socket, []), do: socket

  defp push_deadline_notification(socket, alerts) do
    {overdue, near} =
      Enum.reduce(alerts, {0, 0}, fn alert, {o, n} ->
        case alert.status do
          :overdue -> {o + 1, n}
          :near -> {o, n + 1}
        end
      end)

    push_event(socket, "notify-deadlines", %{overdue: overdue, near: near})
  end

  defp deadline_status_label(:overdue), do: gettext("超過")
  defp deadline_status_label(:near), do: gettext("近接")

  defp days_until_label(days) when days < 0 do
    gettext("%{days}日超過", days: abs(days))
  end

  defp days_until_label(0), do: gettext("本日期限")
  defp days_until_label(days), do: gettext("あと%{days}日", days: days)
end
