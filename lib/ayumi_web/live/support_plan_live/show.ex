defmodule AyumiWeb.SupportPlanLive.Show do
  use AyumiWeb, :live_view

  alias Ayumi.Accounts.User
  alias Ayumi.Plans
  alias Ayumi.Plans.Goal
  alias Ayumi.Plans.GoalProgress
  alias Ayumi.Plans.GoalProgressStage

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

  @impl true
  def handle_event(
        "record_goal_progress",
        %{"goal_id" => goal_id, "goal_progress" => params},
        socket
      ) do
    plan = socket.assigns.support_plan
    now = DateTime.utc_now(:second)

    progress_params =
      params
      |> Map.put("goal_id", goal_id)
      |> Map.put("recorded_by_id", socket.assigns.current_scope.user.id)
      |> Map.put("recorded_at", now)

    case Plans.record_goal_progress(progress_params) do
      {:ok, _progress} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("進捗を記録しました"))
         |> load(plan.id)}

      {:error, changeset} ->
        goal_progress_forms =
          Map.put(
            socket.assigns.goal_progress_forms,
            String.to_integer(goal_id),
            to_form(changeset)
          )

        {:noreply, assign(socket, :goal_progress_forms, goal_progress_forms)}
    end
  end

  defp load(socket, id) do
    support_plan = Plans.get_support_plan!(id)
    goals = Plans.list_goals(support_plan)

    socket
    |> assign(:page_title, gettext("支援計画"))
    |> assign(:support_plan, support_plan)
    |> assign(:goals, goals)
    |> assign(:goal_form, to_form(Plans.change_goal(%Goal{})))
    |> assign(:goal_progress_forms, goal_progress_forms(goals))
    |> assign(:latest_goal_progress_by_goal, Plans.latest_goal_progress_by_goal(goals))
    |> assign(:goal_progress_history_by_goal, goal_progress_history_by_goal(goals))
  end

  defp goal_progress_forms(goals) do
    Map.new(goals, fn goal ->
      {goal.id, to_form(Plans.change_goal_progress(%GoalProgress{}))}
    end)
  end

  defp goal_progress_history_by_goal(goals) do
    Map.new(goals, fn goal -> {goal.id, Plans.list_goal_progress(goal)} end)
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

      <div id="goals" class="mt-4 space-y-5">
        <div
          :for={goal <- @goals}
          id={"goal-#{goal.id}"}
          class="rounded-lg border border-zinc-200 bg-white p-4 shadow-sm transition hover:shadow-md"
        >
          <div class="flex flex-col gap-3 md:flex-row md:items-start md:justify-between">
            <div>
              <h3 class="text-base font-semibold text-zinc-900">{goal.description}</h3>
              <p class="mt-1 text-sm text-zinc-600">
                {gettext("現在の進捗")}:
                <span class="font-medium text-zinc-900">
                  {goal_progress_label(@latest_goal_progress_by_goal[goal.id])}
                </span>
              </p>
            </div>

            <.form
              for={@goal_progress_forms[goal.id]}
              id={"goal-progress-form-#{goal.id}"}
              phx-submit="record_goal_progress"
              class="grid gap-3 rounded-md bg-zinc-50 p-3 md:min-w-96"
            >
              <input type="hidden" name="goal_id" value={goal.id} />
              <.input
                field={@goal_progress_forms[goal.id][:stage]}
                type="select"
                label={gettext("進捗ステージ")}
                prompt={gettext("選択してください")}
                options={GoalProgressStage.options()}
              />
              <.input
                field={@goal_progress_forms[goal.id][:note]}
                type="textarea"
                label={gettext("所見")}
              />
              <.button id={"record-goal-progress-#{goal.id}"} phx-disable-with={gettext("記録中...")}>
                {gettext("進捗を記録")}
              </.button>
            </.form>
          </div>

          <div class="mt-4">
            <h4 class="text-sm font-semibold text-zinc-800">{gettext("進捗履歴")}</h4>
            <div id={"goal-progress-history-#{goal.id}"} class="mt-2 space-y-2">
              <div
                :if={@goal_progress_history_by_goal[goal.id] == []}
                class="rounded-md border border-dashed border-zinc-300 px-3 py-2 text-sm text-zinc-500"
              >
                {gettext("まだ進捗記録はありません")}
              </div>

              <div
                :for={progress <- @goal_progress_history_by_goal[goal.id]}
                id={"goal-progress-#{progress.id}"}
                class="rounded-md border border-zinc-100 px-3 py-2 text-sm"
              >
                <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
                  <span class="font-medium text-zinc-900">
                    {GoalProgressStage.label(progress.stage)}
                  </span>
                  <span class="text-zinc-600">{User.display_name(progress.recorded_by)}</span>
                  <span class="text-zinc-500">{progress.recorded_at}</span>
                </div>
                <p :if={progress.note not in [nil, ""]} class="mt-1 whitespace-pre-line text-zinc-700">
                  {progress.note}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

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

  defp goal_progress_label(nil), do: gettext("未記録")
  defp goal_progress_label(progress), do: GoalProgressStage.label(progress.stage)
end
