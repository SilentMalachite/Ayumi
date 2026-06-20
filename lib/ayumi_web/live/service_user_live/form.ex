defmodule AyumiWeb.ServiceUserLive.Form do
  use AyumiWeb, :live_view

  alias Ayumi.Accounts.User
  alias Ayumi.Plans

  alias Ayumi.Plans.{
    CertificateKind,
    DisabilityCertificate,
    EnrollmentStatus,
    Gender,
    ServiceUser,
    SupportCategory
  }

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    service_user = %ServiceUser{}

    changeset =
      service_user
      |> Plans.change_service_user()
      |> Ecto.Changeset.put_assoc(:disability_certificates, [%DisabilityCertificate{}])

    socket
    |> assign(:page_title, gettext("利用者の新規登録"))
    |> assign(:service_user, service_user)
    |> assign(:other_editors, [])
    |> assign_form(changeset)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    service_user = Plans.get_service_user!(id)

    socket
    |> assign(:page_title, gettext("利用者の編集"))
    |> assign(:service_user, service_user)
    |> track_editing(service_user.id)
    |> assign_form(edit_changeset(service_user))
  end

  @impl true
  def handle_event("validate", %{"service_user" => params}, socket) do
    changeset =
      socket.assigns.service_user
      |> Plans.change_service_user(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"service_user" => params}, socket) do
    save_service_user(socket, socket.assigns.live_action, params)
  end

  defp save_service_user(socket, :new, params) do
    case Plans.create_service_user(params) do
      {:ok, service_user} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("利用者を登録しました"))
         |> push_navigate(to: ~p"/service_users/#{service_user.id}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_service_user(socket, :edit, params) do
    case Plans.update_service_user(socket.assigns.service_user, params) do
      {:ok, service_user} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("利用者情報を更新しました"))
         |> push_navigate(to: ~p"/service_users/#{service_user.id}")}

      {:error, :stale} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           gettext("他のスタッフが先にこの利用者を更新しました。最新を読み込みました。内容を確認して保存し直してください。")
         )
         |> reload_edit_form()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign_other_editors(socket)}
  end

  defp edit_changeset(%ServiceUser{} = service_user) do
    if service_user.disability_certificates == [] do
      Plans.change_service_user(service_user)
      |> Ecto.Changeset.put_assoc(:disability_certificates, [%DisabilityCertificate{}])
    else
      Plans.change_service_user(service_user)
    end
  end

  defp track_editing(socket, service_user_id) do
    topic = AyumiWeb.Presence.editing_topic(:service_user, service_user_id)

    if connected?(socket) do
      user = socket.assigns.current_scope.user
      Phoenix.PubSub.subscribe(Ayumi.PubSub, topic)

      AyumiWeb.Presence.track(self(), topic, to_string(user.id), %{
        name: User.display_name(user)
      })
    end

    socket
    |> assign(:editing_topic, topic)
    |> assign_other_editors()
  end

  defp assign_other_editors(socket) do
    self_key = to_string(socket.assigns.current_scope.user.id)

    others =
      socket.assigns.editing_topic
      |> AyumiWeb.Presence.list()
      |> Enum.reject(fn {key, _presence} -> key == self_key end)
      |> Enum.flat_map(fn {_key, %{metas: metas}} -> Enum.map(metas, & &1.name) end)
      |> Enum.uniq()

    assign(socket, :other_editors, others)
  end

  defp reload_edit_form(socket) do
    service_user = Plans.get_service_user!(socket.assigns.service_user.id)

    socket
    |> assign(:service_user, service_user)
    |> assign_form(edit_changeset(service_user))
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>{@page_title}</.header>

      <div
        :if={@other_editors != []}
        class="rounded border border-yellow-400 bg-yellow-100 px-4 py-2 my-4 text-yellow-800"
        role="alert"
      >
        {gettext("⚠ %{names} さんが現在この利用者を編集中です。同時に保存すると、一方の変更が反映されない場合があります。",
          names: Enum.join(@other_editors, "、")
        )}
      </div>

      <.form for={@form} id="service-user-form" phx-change="validate" phx-submit="save">
        <section class="my-6">
          <h2 class="text-lg font-semibold mb-2">{gettext("基本")}</h2>
          <.input field={@form[:name]} type="text" label={gettext("氏名")} />
          <.input field={@form[:name_kana]} type="text" label={gettext("ふりがな")} />
          <.input field={@form[:birthdate]} type="date" label={gettext("生年月日")} />
          <.input
            field={@form[:gender]}
            type="select"
            label={gettext("性別")}
            options={Gender.options()}
            prompt={gettext("選択してください")}
          />
          <.input
            field={@form[:enrollment_status]}
            type="select"
            label={gettext("在籍状態")}
            options={EnrollmentStatus.options()}
          />
          <.input
            field={@form[:enrollment_start_date]}
            type="date"
            label={gettext("利用開始日")}
          />
        </section>

        <section class="my-6">
          <h2 class="text-lg font-semibold mb-2">{gettext("連絡先")}</h2>
          <.input field={@form[:postal_code]} type="text" label={gettext("郵便番号")} />
          <.input field={@form[:address]} type="text" label={gettext("住所")} />
          <.input field={@form[:phone]} type="text" label={gettext("電話番号")} />
          <.input field={@form[:emergency_contact_name]} type="text" label={gettext("緊急連絡先 氏名")} />
          <.input field={@form[:emergency_contact_relation]} type="text" label={gettext("続柄")} />
          <.input field={@form[:emergency_contact_phone]} type="text" label={gettext("緊急連絡先 電話")} />
        </section>

        <section class="my-6">
          <h2 class="text-lg font-semibold mb-2">{gettext("受給者証")}</h2>
          <.input field={@form[:recipient_cert_number]} type="text" label={gettext("受給者証番号")} />
          <.input field={@form[:recipient_cert_municipality]} type="text" label={gettext("支給市町村")} />
          <.input
            field={@form[:disability_support_category]}
            type="select"
            label={gettext("障害支援区分")}
            options={SupportCategory.options()}
            prompt={gettext("選択してください")}
          />
          <.input field={@form[:benefit_amount]} type="text" label={gettext("支給量")} />
          <.input field={@form[:recipient_cert_expiry]} type="date" label={gettext("受給者証 有効期限")} />
        </section>

        <section class="my-6">
          <h2 class="text-lg font-semibold mb-2">{gettext("障害者手帳")}</h2>
          <.inputs_for :let={cert} field={@form[:disability_certificates]}>
            <.input
              field={cert[:kind]}
              type="select"
              label={gettext("手帳の種類")}
              options={CertificateKind.options()}
              prompt={gettext("選択してください")}
            />
            <.input field={cert[:number]} type="text" label={gettext("手帳番号")} />
            <.input field={cert[:disability_name]} type="text" label={gettext("障害種類・障害名")} />
            <.input field={cert[:grade]} type="text" label={gettext("等級")} />
          </.inputs_for>
        </section>

        <section class="my-6">
          <h2 class="text-lg font-semibold mb-2">{gettext("医療")}</h2>
          <.input field={@form[:clinic_name]} type="text" label={gettext("通院先")} />
          <.input field={@form[:attending_physician]} type="text" label={gettext("主治医")} />
          <.input field={@form[:medication_notes]} type="textarea" label={gettext("服薬・特記")} />
        </section>

        <section class="my-6">
          <h2 class="text-lg font-semibold mb-2">{gettext("その他")}</h2>
          <.input field={@form[:consultation_office]} type="text" label={gettext("相談支援事業所")} />
          <.input field={@form[:consultation_staff]} type="text" label={gettext("担当相談員")} />
          <.input field={@form[:notes]} type="textarea" label={gettext("備考")} />
        </section>

        <.button phx-disable-with={gettext("保存中...")}>{gettext("保存")}</.button>
      </.form>
    </Layouts.app>
    """
  end
end
