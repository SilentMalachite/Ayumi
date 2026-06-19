defmodule AyumiWeb.ServiceUserLive.Show do
  use AyumiWeb, :live_view

  alias Ayumi.Accounts.User
  alias Ayumi.Plans
  alias Ayumi.Plans.{CertificateKind, Gender, ServiceUser, SupportCategory}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    service_user = Plans.get_service_user!(id)

    {:ok,
     socket
     |> assign(:page_title, service_user.name)
     |> assign(:service_user, service_user)
     |> assign(:today, Date.utc_today())
     |> assign(:support_plans, Plans.list_support_plans_for_user(service_user))}
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
          <.button navigate={~p"/service_users/#{@service_user.id}/support_plans/new"}>
            {gettext("支援計画を作成")}
          </.button>
        </:actions>
      </.header>

      <section class="my-6">
        <h2 class="text-lg font-semibold mb-2">{gettext("基本")}</h2>
        <dl>
          <.field_row label={gettext("生年月日")}>{format_birthdate(@service_user, @today)}</.field_row>
          <.field_row label={gettext("性別")}>{Gender.label(@service_user.gender)}</.field_row>
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

      <section class="my-6">
        <h2 class="text-lg font-semibold mb-2">{gettext("支援計画")}</h2>
        <.table id="support-plans" rows={@support_plans}>
          <:col :let={plan} label={gettext("計画期間")}>
            {plan.period_start} 〜 {plan.period_end}
          </:col>
          <:col :let={plan} label={gettext("担当者")}>{User.display_name(plan.staff)}</:col>
          <:col :let={plan} label={gettext("長期目標")}>{plan.long_term_goal}</:col>
          <:col :let={plan} label={gettext("次回モニタリング")}>{plan.next_monitoring_date}</:col>
          <:col :let={plan} label="">
            <.link navigate={~p"/support_plans/#{plan.id}"}>{gettext("詳細")}</.link>
          </:col>
        </.table>
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
end
