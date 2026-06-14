defmodule AyumiWeb.ServiceUserLive.Show do
  use AyumiWeb, :live_view

  alias Ayumi.Accounts.User
  alias Ayumi.Plans

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    service_user = Plans.get_service_user!(id)

    {:ok,
     socket
     |> assign(:page_title, service_user.name)
     |> assign(:service_user, service_user)
     |> assign(:support_plans, Plans.list_support_plans_for_user(service_user))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@service_user.name}
        <:subtitle>{@service_user.name_kana}</:subtitle>
        <:actions>
          <.button navigate={~p"/service_users/#{@service_user.id}/support_plans/new"}>
            支援計画を作成
          </.button>
        </:actions>
      </.header>

      <.table id="support-plans" rows={@support_plans}>
        <:col :let={plan} label="計画期間">
          {plan.period_start} 〜 {plan.period_end}
        </:col>
        <:col :let={plan} label="担当者">{User.display_name(plan.staff)}</:col>
        <:col :let={plan} label="長期目標">{plan.long_term_goal}</:col>
        <:col :let={plan} label="次回モニタリング">{plan.next_monitoring_date}</:col>
        <:col :let={plan} label="">
          <.link navigate={~p"/support_plans/#{plan.id}"}>詳細</.link>
        </:col>
      </.table>
    </Layouts.app>
    """
  end
end
