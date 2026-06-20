defmodule AyumiWeb.ServiceUserLive.Show do
  use AyumiWeb, :live_view

  alias Ayumi.Accounts.User
  alias Ayumi.Plans

  alias Ayumi.Plans.{
    CertificateKind,
    EnrollmentStatus,
    Gender,
    GoalProgressStage,
    PlanPhaseStage,
    ServiceUser,
    SupportCategory,
    SupportRecordCategory
  }

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    service_user = Plans.get_service_user!(id)
    today = Date.utc_today()
    support_plans = Plans.list_support_plans_for_user(service_user)
    current_plan = List.first(support_plans)

    goals =
      if current_plan, do: Plans.list_goals(current_plan), else: []

    latest_progress =
      if goals != [], do: Plans.latest_goal_progress_by_goal(goals), else: %{}

    monitoring_status =
      if current_plan && current_plan.next_monitoring_date,
        do: Plans.monitoring_deadline_status(current_plan.next_monitoring_date, today, 30),
        else: nil

    cert_status =
      if service_user.recipient_cert_expiry,
        do: Plans.monitoring_deadline_status(service_user.recipient_cert_expiry, today, 60),
        else: nil

    {:ok,
     socket
     |> assign(:page_title, service_user.name)
     |> assign(:service_user, service_user)
     |> assign(:today, today)
     |> assign(:support_plans, support_plans)
     |> assign(:current_plan, current_plan)
     |> assign(:goals, goals)
     |> assign(:latest_progress, latest_progress)
     |> assign(:recent_goal_progress, Plans.list_recent_goal_progress_for_user(service_user.id))
     |> assign(
       :recent_phase_events,
       Plans.list_recent_plan_phase_events_for_user(service_user.id)
     )
     |> assign(:recent_support_records, Plans.list_recent_support_records(service_user.id))
     |> assign(:monitoring_status, monitoring_status)
     |> assign(:cert_status, cert_status)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@service_user.name}
        <:subtitle>{@service_user.name_kana}</:subtitle>
        <:actions :if={Ayumi.Accounts.Scope.manager?(@current_scope)}>
          <.button navigate={~p"/service_users/#{@service_user.id}/edit"}>{gettext("編集")}</.button>
          <.button
            :if={@service_user.enrollment_status != :withdrawn}
            navigate={~p"/service_users/#{@service_user.id}/support_plans/new"}
          >
            {gettext("支援計画を作成")}
          </.button>
        </:actions>
      </.header>

      <%!-- 1. 基本情報 --%>
      <section class="my-6">
        <h2 class="text-lg font-semibold mb-2">{gettext("基本")}</h2>
        <dl>
          <.field_row label={gettext("生年月日")}>{format_birthdate(@service_user, @today)}</.field_row>
          <.field_row label={gettext("性別")}>{Gender.label(@service_user.gender)}</.field_row>
          <.field_row label={gettext("在籍状態")}>
            {EnrollmentStatus.label(@service_user.enrollment_status)}
          </.field_row>
          <.field_row label={gettext("利用開始日")}>{@service_user.enrollment_start_date}</.field_row>
        </dl>
      </section>

      <section class="my-6">
        <h2 class="text-lg font-semibold mb-2">{gettext("連絡先")}</h2>
        <dl>
          <.field_row label={gettext("郵便番号")}>{@service_user.postal_code}</.field_row>
          <.field_row label={gettext("住所")}>{@service_user.address}</.field_row>
          <.field_row label={gettext("電話番号")}>{@service_user.phone}</.field_row>
          <.field_row label={gettext("緊急連絡先 氏名")}>
            {@service_user.emergency_contact_name}
          </.field_row>
          <.field_row label={gettext("続柄")}>{@service_user.emergency_contact_relation}</.field_row>
          <.field_row label={gettext("緊急連絡先 電話")}>
            {@service_user.emergency_contact_phone}
          </.field_row>
        </dl>
      </section>

      <%!-- 2. 期限（この利用者） --%>
      <section class="my-6">
        <h2 class="text-lg font-semibold mb-2">{gettext("期限")}</h2>
        <dl>
          <.field_row label={gettext("受給者証期限")}>
            {@service_user.recipient_cert_expiry}
            <.deadline_badge
              :if={@cert_status && @cert_status != :ok}
              status={@cert_status}
              date={@service_user.recipient_cert_expiry}
              today={@today}
            />
          </.field_row>
          <.field_row label={gettext("次回モニタリング")}>
            {if @current_plan, do: @current_plan.next_monitoring_date}
            <.deadline_badge
              :if={@monitoring_status && @monitoring_status != :ok}
              status={@monitoring_status}
              date={@current_plan && @current_plan.next_monitoring_date}
              today={@today}
            />
          </.field_row>
        </dl>
      </section>

      <%!-- 3. 受給者証・手帳 --%>
      <section class="my-6">
        <h2 class="text-lg font-semibold mb-2">{gettext("受給者証")}</h2>
        <dl>
          <.field_row label={gettext("受給者証番号")}>{@service_user.recipient_cert_number}</.field_row>
          <.field_row label={gettext("支給市町村")}>
            {@service_user.recipient_cert_municipality}
          </.field_row>
          <.field_row label={gettext("障害支援区分")}>
            {SupportCategory.label(@service_user.disability_support_category)}
          </.field_row>
          <.field_row label={gettext("支給量")}>{@service_user.benefit_amount}</.field_row>
          <.field_row label={gettext("有効期限")}>{@service_user.recipient_cert_expiry}</.field_row>
        </dl>
      </section>

      <section class="my-6">
        <h2 class="text-lg font-semibold mb-2">{gettext("障害者手帳")}</h2>
        <.table
          :if={@service_user.disability_certificates != []}
          id="disability-certificates"
          rows={@service_user.disability_certificates}
        >
          <:col :let={cert} label={gettext("種類")}>{CertificateKind.label(cert.kind)}</:col>
          <:col :let={cert} label={gettext("手帳番号")}>{cert.number}</:col>
          <:col :let={cert} label={gettext("障害名")}>{cert.disability_name}</:col>
          <:col :let={cert} label={gettext("等級")}>{cert.grade}</:col>
        </.table>
        <p :if={@service_user.disability_certificates == []} class="text-base-content/60">
          {gettext("登録なし")}
        </p>
      </section>

      <section class="my-6">
        <h2 class="text-lg font-semibold mb-2">{gettext("医療")}</h2>
        <dl>
          <.field_row label={gettext("通院先")}>{@service_user.clinic_name}</.field_row>
          <.field_row label={gettext("主治医")}>{@service_user.attending_physician}</.field_row>
          <.field_row label={gettext("服薬・特記")}>{@service_user.medication_notes}</.field_row>
        </dl>
      </section>

      <section class="my-6">
        <h2 class="text-lg font-semibold mb-2">{gettext("その他")}</h2>
        <dl>
          <.field_row label={gettext("相談支援事業所")}>{@service_user.consultation_office}</.field_row>
          <.field_row label={gettext("担当相談員")}>{@service_user.consultation_staff}</.field_row>
          <.field_row label={gettext("備考")}>{@service_user.notes}</.field_row>
        </dl>
      </section>

      <%!-- 4. 現行の支援計画と目標 --%>
      <section class="my-6">
        <h2 class="text-lg font-semibold mb-2">{gettext("支援計画")}</h2>
        <div :if={@current_plan} class="mb-4 p-4 border rounded-lg">
          <h3 class="font-semibold mb-2">{gettext("現行計画")}</h3>
          <dl>
            <.field_row label={gettext("担当者")}>{User.display_name(@current_plan.staff)}</.field_row>
            <.field_row label={gettext("計画期間")}>
              {@current_plan.period_start} 〜 {@current_plan.period_end}
            </.field_row>
            <.field_row label={gettext("長期目標")}>{@current_plan.long_term_goal}</.field_row>
            <.field_row label={gettext("次回モニタリング")}>
              {@current_plan.next_monitoring_date}
            </.field_row>
          </dl>

          <h4 class="font-medium mt-4 mb-2">{gettext("目標")}</h4>
          <ul :if={@goals != []} class="space-y-2">
            <li :for={goal <- @goals} class="flex items-center gap-2">
              <span>{goal.description}</span>
              <span class="badge badge-sm">
                {GoalProgressStage.label((@latest_progress[goal.id] || %{stage: nil}).stage) ||
                  gettext("未記録")}
              </span>
            </li>
          </ul>
          <p :if={@goals == []} class="text-base-content/60">{gettext("目標なし")}</p>

          <div class="mt-3">
            <.link navigate={~p"/support_plans/#{@current_plan.id}"} class="link link-primary text-sm">
              {gettext("計画詳細を見る →")}
            </.link>
          </div>
        </div>

        <details :if={length(@support_plans) > 1} class="mb-4">
          <summary class="cursor-pointer text-sm text-base-content/70">
            {gettext("過去の計画（%{count}件）", count: length(@support_plans) - 1)}
          </summary>
          <.table id="past-support-plans" rows={tl(@support_plans)}>
            <:col :let={plan} label={gettext("計画期間")}>
              {plan.period_start} 〜 {plan.period_end}
            </:col>
            <:col :let={plan} label={gettext("担当者")}>{User.display_name(plan.staff)}</:col>
            <:col :let={plan} label={gettext("長期目標")}>{plan.long_term_goal}</:col>
            <:col :let={plan} label="">
              <.link navigate={~p"/support_plans/#{plan.id}"}>{gettext("詳細")}</.link>
            </:col>
          </.table>
        </details>

        <p :if={@current_plan == nil} class="text-base-content/60">{gettext("支援計画なし")}</p>
      </section>

      <%!-- 5. 進捗・フェーズ履歴（最近） --%>
      <section class="my-6">
        <h2 class="text-lg font-semibold mb-2">{gettext("進捗・フェーズ履歴")}</h2>

        <div :if={@recent_goal_progress != [] || @recent_phase_events != []}>
          <.table
            :if={@recent_goal_progress != []}
            id="recent-goal-progress"
            rows={@recent_goal_progress}
          >
            <:col :let={gp} label={gettext("目標")}>{gp.goal.description}</:col>
            <:col :let={gp} label={gettext("ステージ")}>{GoalProgressStage.label(gp.stage)}</:col>
            <:col :let={gp} label={gettext("記録者")}>{User.display_name(gp.recorded_by)}</:col>
            <:col :let={gp} label={gettext("所見")}>{gp.note}</:col>
          </.table>

          <.table
            :if={@recent_phase_events != []}
            id="recent-phase-events"
            rows={@recent_phase_events}
          >
            <:col :let={pe} label={gettext("計画")}>{pe.support_plan.long_term_goal}</:col>
            <:col :let={pe} label={gettext("ステージ")}>{PlanPhaseStage.label(pe.stage)}</:col>
            <:col :let={pe} label={gettext("記録者")}>{User.display_name(pe.recorded_by)}</:col>
            <:col :let={pe} label={gettext("所見")}>{pe.note}</:col>
          </.table>
        </div>

        <p
          :if={@recent_goal_progress == [] && @recent_phase_events == []}
          class="text-base-content/60"
        >
          {gettext("履歴なし")}
        </p>
      </section>

      <%!-- 6. 支援記録（最近） --%>
      <section class="my-6">
        <h2 class="text-lg font-semibold mb-2">{gettext("支援記録")}</h2>
        <.table
          :if={@recent_support_records != []}
          id="recent-support-records"
          rows={@recent_support_records}
        >
          <:col :let={r} label={gettext("日時")}>
            {Calendar.strftime(r.recorded_at, "%Y-%m-%d %H:%M")}
          </:col>
          <:col :let={r} label={gettext("カテゴリ")}>{SupportRecordCategory.label(r.category)}</:col>
          <:col :let={r} label={gettext("内容")}>{String.slice(r.content, 0..50)}</:col>
          <:col :let={r} label={gettext("記録者")}>{User.display_name(r.recorded_by)}</:col>
        </.table>
        <p :if={@recent_support_records == []} class="text-base-content/60">
          {gettext("支援記録なし")}
        </p>
        <div class="mt-3">
          <.link navigate={~p"/support_records"} class="link link-primary text-sm">
            {gettext("支援記録表を見る →")}
          </.link>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp field_row(assigns) do
    ~H"""
    <div class="flex gap-2 py-1">
      <dt class="w-40 shrink-0 font-medium text-base-content/70">{@label}</dt>
      <dd>{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  defp format_birthdate(%ServiceUser{birthdate: nil}, _today), do: nil

  defp format_birthdate(%ServiceUser{birthdate: birthdate} = service_user, today),
    do:
      gettext("%{birthdate}（%{age}歳）",
        birthdate: birthdate,
        age: ServiceUser.age(service_user, today)
      )

  defp deadline_badge(assigns) do
    days_until = Date.diff(assigns.date, assigns.today)
    assigns = assign(assigns, :days_until, days_until)

    ~H"""
    <span class={[
      "badge badge-sm ml-2",
      @status == :overdue && "badge-error",
      @status == :near && "badge-warning"
    ]}>
      {deadline_status_label(@status)}（{days_until_label(@days_until)}）
    </span>
    """
  end

  defp deadline_status_label(:overdue), do: gettext("超過")
  defp deadline_status_label(:near), do: gettext("近接")

  defp days_until_label(days) when days < 0, do: gettext("%{days}日超過", days: abs(days))
  defp days_until_label(0), do: gettext("本日期限")
  defp days_until_label(days), do: gettext("あと%{days}日", days: days)
end
