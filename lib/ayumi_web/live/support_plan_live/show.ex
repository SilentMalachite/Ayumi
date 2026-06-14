defmodule AyumiWeb.SupportPlanLive.Show do
  use AyumiWeb, :live_view

  alias Ayumi.Accounts.User
  alias Ayumi.Plans
  alias Ayumi.Plans.Goal

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, load(socket, id)}
  end

  @impl true
  def handle_event("add_goal", %{"goal" => params}, socket) do
    plan = socket.assigns.support_plan
    goal_params = Map.put(params, "support_plan_id", plan.id)

    case Plans.create_goal(goal_params) do
      {:ok, _goal} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("短期目標を追加しました"))
         |> load(plan.id)}

      {:error, changeset} ->
        {:noreply, assign(socket, :goal_form, to_form(changeset))}
    end
  end

  defp load(socket, id) do
    support_plan = Plans.get_support_plan!(id)

    socket
    |> assign(:page_title, gettext("支援計画"))
    |> assign(:support_plan, support_plan)
    |> assign(:goals, Plans.list_goals(support_plan))
    |> assign(:goal_form, to_form(Plans.change_goal(%Goal{})))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {gettext("支援計画")}
        <:subtitle>
          {gettext("%{user} ／ 担当 %{staff}",
            user: @support_plan.service_user.name,
            staff: User.display_name(@support_plan.staff)
          )}
        </:subtitle>
      </.header>

      <.list>
        <:item title={gettext("計画期間")}>
          {@support_plan.period_start} 〜 {@support_plan.period_end}
        </:item>
        <:item title={gettext("長期目標")}>{@support_plan.long_term_goal}</:item>
        <:item title={gettext("次回モニタリング予定日")}>{@support_plan.next_monitoring_date}</:item>
      </.list>

      <div class="mt-8">
        <.header>{gettext("短期目標")}</.header>
      </div>

      <.table id="goals" rows={@goals}>
        <:col :let={goal} label={gettext("内容")}>{goal.description}</:col>
      </.table>

      <.form
        for={@goal_form}
        id="goal-form"
        phx-submit="add_goal"
        class="mt-4 flex gap-2 items-end"
      >
        <.input field={@goal_form[:description]} type="text" label={gettext("短期目標を追加")} />
        <.button>{gettext("追加")}</.button>
      </.form>
    </Layouts.app>
    """
  end
end
