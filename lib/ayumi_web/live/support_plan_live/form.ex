defmodule AyumiWeb.SupportPlanLive.Form do
  use AyumiWeb, :live_view

  alias Ayumi.Accounts
  alias Ayumi.Accounts.User
  alias Ayumi.Plans
  alias Ayumi.Plans.SupportPlan

  @impl true
  def mount(%{"service_user_id" => service_user_id}, _session, socket) do
    service_user = Plans.get_service_user!(service_user_id)

    if service_user.enrollment_status == :withdrawn do
      {:ok, redirect_withdrawn(socket, service_user)}
    else
      {:ok,
       socket
       |> assign(:page_title, gettext("支援計画の作成"))
       |> assign(:service_user, service_user)
       |> assign(:staff_options, staff_options())
       |> assign_form(Plans.change_support_plan(%SupportPlan{}))}
    end
  end

  @impl true
  def handle_event("validate", %{"support_plan" => params}, socket) do
    changeset =
      %SupportPlan{}
      |> Plans.change_support_plan(with_service_user(params, socket))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"support_plan" => params}, socket) do
    service_user = socket.assigns.service_user

    if service_user.enrollment_status == :withdrawn do
      {:noreply, redirect_withdrawn(socket, service_user)}
    else
      case Plans.create_support_plan(with_service_user(params, socket)) do
        {:ok, _plan} ->
          {:noreply,
           socket
           |> put_flash(:info, gettext("支援計画を作成しました"))
           |> push_navigate(to: ~p"/service_users/#{service_user.id}")}

        {:error, changeset} ->
          {:noreply, assign_form(socket, changeset)}
      end
    end
  end

  defp redirect_withdrawn(socket, service_user) do
    socket
    |> put_flash(:error, gettext("退所者には支援計画を作成できません"))
    |> push_navigate(to: ~p"/service_users/#{service_user.id}")
  end

  defp with_service_user(params, socket),
    do: Map.put(params, "service_user_id", socket.assigns.service_user.id)

  defp staff_options do
    Accounts.list_users() |> Enum.map(&{User.display_name(&1), &1.id})
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {gettext("支援計画の作成")}
        <:subtitle>{@service_user.name}</:subtitle>
      </.header>

      <.form for={@form} id="support-plan-form" phx-change="validate" phx-submit="save">
        <.input
          field={@form[:staff_id]}
          type="select"
          label={gettext("担当者")}
          options={@staff_options}
          prompt={gettext("選択してください")}
        />
        <.input field={@form[:period_start]} type="date" label={gettext("計画開始日")} />
        <.input field={@form[:period_end]} type="date" label={gettext("計画終了日")} />
        <.input field={@form[:long_term_goal]} type="textarea" label={gettext("長期目標")} />
        <.input
          field={@form[:next_monitoring_date]}
          type="date"
          label={gettext("次回モニタリング予定日")}
        />
        <.button phx-disable-with={gettext("保存中...")}>{gettext("保存")}</.button>
      </.form>
    </Layouts.app>
    """
  end
end
