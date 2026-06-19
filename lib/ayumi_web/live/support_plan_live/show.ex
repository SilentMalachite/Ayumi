defmodule AyumiWeb.SupportPlanLive.Show do
  use AyumiWeb, :live_view

  alias Ayumi.Accounts.User
  alias Ayumi.Plans
  alias Ayumi.Plans.Goal
  alias Ayumi.Plans.GoalProgress
  alias Ayumi.Plans.PlanPhaseEvent

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, load(socket, id)}
  end

  @impl true
  def handle_event("add_goal", %{"goal" => params}, socket) do
    if Ayumi.Accounts.Scope.manager?(socket.assigns.current_scope) do
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
    else
      {:noreply, put_flash(socket, :error, gettext("この操作にはサービス管理責任者の権限が必要です"))}
    end
  end

  @impl true
  def handle_event("record_plan_phase_event", %{"plan_phase_event" => params}, socket) do
    plan = socket.assigns.support_plan
    now = DateTime.utc_now(:second)

    event_params =
      params
      |> Map.put("support_plan_id", plan.id)
      |> Map.put("recorded_by_id", socket.assigns.current_scope.user.id)
      |> Map.put("recorded_at", now)

    case Plans.record_plan_phase_event(event_params) do
      {:ok, _event} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("ステージを記録しました"))
         |> load(plan.id)}

      {:error, changeset} ->
        {:noreply, assign(socket, :plan_phase_form, to_form(changeset))}
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

    case Plans.record_goal_progress_for_plan(plan, progress_params) do
      {:ok, _progress} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("進捗を記録しました"))
         |> load(plan.id)}

      {:error, changeset} ->
        case existing_goal_progress_form_key(goal_id, socket.assigns.goal_progress_forms) do
          {:ok, goal_id} ->
            goal_progress_forms =
              Map.put(socket.assigns.goal_progress_forms, goal_id, to_form(changeset))

            {:noreply, assign(socket, :goal_progress_forms, goal_progress_forms)}

          :error ->
            {:noreply, put_flash(socket, :error, gettext("進捗を記録できませんでした"))}
        end
    end
  end

  def handle_event("record_goal_progress", _params, socket) do
    {:noreply, put_flash(socket, :error, gettext("進捗を記録できませんでした"))}
  end

  defp load(socket, id) do
    support_plan = Plans.get_support_plan!(id)
    goals = Plans.list_goals(support_plan)
    phase_events = Plans.list_plan_phase_events(support_plan)

    socket
    |> assign(:page_title, gettext("支援計画"))
    |> assign(:support_plan, support_plan)
    |> assign(:goals, goals)
    |> assign(:goal_form, to_form(Plans.change_goal(%Goal{})))
    |> assign(:goal_progress_forms, goal_progress_forms(goals))
    |> assign(:latest_goal_progress_by_goal, Plans.latest_goal_progress_by_goal(goals))
    |> assign(:goal_progress_history_by_goal, goal_progress_history_by_goal(goals))
    |> assign(:plan_phase_events, phase_events)
    |> assign(:current_plan_phase, Plans.current_plan_stage(phase_events))
    |> assign(:plan_phase_form, to_form(Plans.change_plan_phase_event(%PlanPhaseEvent{})))
  end

  defp goal_progress_forms(goals) do
    Map.new(goals, fn goal ->
      {goal.id, to_form(Plans.change_goal_progress(%GoalProgress{}))}
    end)
  end

  defp goal_progress_history_by_goal(goals) do
    Plans.list_goal_progress_for_goals(goals)
  end

  defp existing_goal_progress_form_key(goal_id, goal_progress_forms) do
    with {:ok, goal_id} <- parse_goal_id(goal_id),
         true <- Map.has_key?(goal_progress_forms, goal_id) do
      {:ok, goal_id}
    else
      _ -> :error
    end
  end

  defp parse_goal_id(goal_id) when is_integer(goal_id), do: {:ok, goal_id}

  defp parse_goal_id(goal_id) when is_binary(goal_id) do
    case Integer.parse(String.trim(goal_id)) do
      {goal_id, ""} -> {:ok, goal_id}
      _ -> :error
    end
  end

  defp parse_goal_id(_goal_id), do: :error

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

      <section
        id="plan-phase-panel"
        class="mt-8 rounded-lg border border-zinc-200 bg-white p-4 shadow-sm"
      >
        <div class="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
          <div>
            <h2 class="text-base font-semibold text-zinc-900">{gettext("計画ライフサイクル")}</h2>
            <p class="mt-1 text-sm text-zinc-600">
              {gettext("現在ステージ")}:
              <span class="font-medium text-zinc-900">{plan_phase_label(@current_plan_phase)}</span>
            </p>
          </div>

          <.form
            for={@plan_phase_form}
            id="plan-phase-form"
            phx-submit="record_plan_phase_event"
            class="grid gap-3 rounded-md bg-zinc-50 p-3 md:min-w-96"
          >
            <.input
              field={@plan_phase_form[:stage]}
              type="select"
              label={gettext("ステージ")}
              prompt={gettext("選択してください")}
              options={plan_phase_stage_options()}
            />
            <.input field={@plan_phase_form[:note]} type="textarea" label={gettext("所見")} />
            <.button id="record-plan-phase" phx-disable-with={gettext("記録中...")}>
              {gettext("ステージを記録")}
            </.button>
          </.form>
        </div>

        <div class="mt-4">
          <h3 class="text-sm font-semibold text-zinc-800">{gettext("ステージ履歴")}</h3>
          <div id="plan-phase-history" class="mt-2 space-y-2">
            <div
              :if={@plan_phase_events == []}
              class="rounded-md border border-dashed border-zinc-300 px-3 py-2 text-sm text-zinc-500"
            >
              {gettext("まだステージ記録はありません")}
            </div>

            <div
              :for={event <- @plan_phase_events}
              id={"plan-phase-event-#{event.id}"}
              class="rounded-md border border-zinc-100 px-3 py-2 text-sm"
            >
              <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
                <span class="font-medium text-zinc-900">{plan_phase_stage_label(event.stage)}</span>
                <span class="text-zinc-600">{User.display_name(event.recorded_by)}</span>
                <span class="text-zinc-500">{event.recorded_at}</span>
              </div>
              <p :if={event.note not in [nil, ""]} class="mt-1 whitespace-pre-line text-zinc-700">
                {event.note}
              </p>
            </div>
          </div>
        </div>
      </section>

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
                options={goal_progress_stage_options()}
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
                    {goal_progress_stage_label(progress.stage)}
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
        :if={Ayumi.Accounts.Scope.manager?(@current_scope)}
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
  defp goal_progress_label(progress), do: goal_progress_stage_label(progress.stage)

  defp goal_progress_stage_options do
    [
      {:not_started, goal_progress_stage_label(:not_started)},
      {:working, goal_progress_stage_label(:working)},
      {:partially_met, goal_progress_stage_label(:partially_met)},
      {:mostly_met, goal_progress_stage_label(:mostly_met)},
      {:met, goal_progress_stage_label(:met)}
    ]
    |> Enum.map(fn {value, label} -> {label, value} end)
  end

  defp goal_progress_stage_label(:not_started), do: gettext("未着手")
  defp goal_progress_stage_label(:working), do: gettext("取組中")
  defp goal_progress_stage_label(:partially_met), do: gettext("一部達成")
  defp goal_progress_stage_label(:mostly_met), do: gettext("概ね達成")
  defp goal_progress_stage_label(:met), do: gettext("達成")

  defp plan_phase_label(nil), do: gettext("未記録")
  defp plan_phase_label(event), do: plan_phase_stage_label(event.stage)

  defp plan_phase_stage_options do
    [
      {:assessment, plan_phase_stage_label(:assessment)},
      {:draft, plan_phase_stage_label(:draft)},
      {:support_meeting, plan_phase_stage_label(:support_meeting)},
      {:consent, plan_phase_stage_label(:consent)},
      {:in_progress, plan_phase_stage_label(:in_progress)},
      {:monitoring, plan_phase_stage_label(:monitoring)},
      {:review, plan_phase_stage_label(:review)}
    ]
    |> Enum.map(fn {value, label} -> {label, value} end)
  end

  defp plan_phase_stage_label(:assessment), do: gettext("アセスメント")
  defp plan_phase_stage_label(:draft), do: gettext("計画原案")
  defp plan_phase_stage_label(:support_meeting), do: gettext("個別支援会議")
  defp plan_phase_stage_label(:consent), do: gettext("説明・同意・交付")
  defp plan_phase_stage_label(:in_progress), do: gettext("支援の実施")
  defp plan_phase_stage_label(:monitoring), do: gettext("モニタリング")
  defp plan_phase_stage_label(:review), do: gettext("見直し")
end
