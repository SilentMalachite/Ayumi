defmodule AyumiWeb.AttendanceLive.Index do
  @moduledoc "利用者別・1か月分の出欠/実績記録票(表示・入力・訂正)。"
  use AyumiWeb, :live_view

  alias Ayumi.Plans
  alias Ayumi.Plans.ProvisionType

  @impl true
  def mount(%{"service_user_id" => id}, _session, socket) do
    service_user = Plans.get_service_user!(id)

    {:ok,
     socket
     |> assign(:service_user, service_user)
     |> assign(:provision_options, [{gettext("（未選択）"), ""} | ProvisionType.options()])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {year, month} = parse_year_month(params)
    sheet = Plans.build_attendance_sheet(socket.assigns.service_user.id, year, month)

    {:noreply,
     socket
     |> assign(:year, year)
     |> assign(:month, month)
     |> assign(:sheet, sheet)
     |> assign(:page_title, gettext("実績記録票 %{y}年%{m}月", y: year, m: month))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {gettext("実績記録票")}
        <:subtitle>
          {@service_user.name} — {gettext("%{y}年%{m}月", y: @year, m: @month)}
        </:subtitle>
        <:actions>
          <.link
            patch={month_path(@service_user, prev_month(@year, @month))}
            class="btn btn-ghost btn-sm"
          >
            {gettext("← 前月")}
          </.link>
          <.link
            patch={month_path(@service_user, next_month(@year, @month))}
            class="btn btn-ghost btn-sm"
          >
            {gettext("翌月 →")}
          </.link>
          <.link navigate={~p"/service_users/#{@service_user.id}"} class="btn btn-ghost btn-sm">
            {gettext("利用者詳細へ戻る")}
          </.link>
        </:actions>
      </.header>

      <section class="my-4 grid grid-cols-2 sm:grid-cols-5 gap-2 text-sm">
        <div>{gettext("利用日数")}: <strong>{@sheet.totals.billable_days}</strong></div>
        <div>{gettext("うち施設外")}: <strong>{@sheet.totals.offsite_days}</strong></div>
        <div>{gettext("送迎 往")}: <strong>{@sheet.totals.pickup_count}</strong></div>
        <div>{gettext("送迎 復")}: <strong>{@sheet.totals.dropoff_count}</strong></div>
        <div>{gettext("欠席時対応")}: <strong>{@sheet.totals.absence_support_count}</strong></div>
      </section>

      <table class="table table-zebra w-full">
        <thead>
          <tr>
            <th>{gettext("日")}</th>
            <th>{gettext("曜")}</th>
            <th>{gettext("提供形態")}</th>
            <th>{gettext("送迎 往")}</th>
            <th>{gettext("送迎 復")}</th>
            <th>{gettext("開始")}</th>
            <th>{gettext("終了")}</th>
            <th>{gettext("備考")}</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={line <- @sheet.lines} class={row_class(line.date)}>
            <td>{line.date.day}</td>
            <td>{weekday_label(line.date)}</td>
            <td colspan="7">
              <form phx-submit="save_day" class="flex flex-wrap gap-2 items-center">
                <input type="hidden" name="date" value={Date.to_iso8601(line.date)} />
                <select
                  name="attendance_record[provision_type]"
                  class="select select-bordered select-sm"
                >
                  <%= for {label, value} <- @provision_options do %>
                    <option value={value} selected={selected_provision?(line, value)}>{label}</option>
                  <% end %>
                </select>
                <label class="label cursor-pointer gap-1">
                  <input type="hidden" name="attendance_record[pickup]" value="false" />
                  <input
                    type="checkbox"
                    name="attendance_record[pickup]"
                    value="true"
                    checked={checked?(line, :pickup)}
                    class="checkbox checkbox-sm"
                  />
                  <span class="label-text">{gettext("往")}</span>
                </label>
                <label class="label cursor-pointer gap-1">
                  <input type="hidden" name="attendance_record[dropoff]" value="false" />
                  <input
                    type="checkbox"
                    name="attendance_record[dropoff]"
                    value="true"
                    checked={checked?(line, :dropoff)}
                    class="checkbox checkbox-sm"
                  />
                  <span class="label-text">{gettext("復")}</span>
                </label>
                <input
                  type="time"
                  name="attendance_record[start_time]"
                  value={time_value(line, :start_time)}
                  class="input input-bordered input-sm w-28"
                />
                <input
                  type="time"
                  name="attendance_record[end_time]"
                  value={time_value(line, :end_time)}
                  class="input input-bordered input-sm w-28"
                />
                <input
                  type="text"
                  name="attendance_record[note]"
                  value={note_value(line)}
                  placeholder={gettext("備考")}
                  class="input input-bordered input-sm flex-1 min-w-32"
                />
                <button type="submit" class="btn btn-primary btn-sm">{gettext("保存")}</button>
              </form>
            </td>
          </tr>
        </tbody>
      </table>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("save_day", %{"date" => date_str, "attendance_record" => attrs}, socket) do
    su = socket.assigns.service_user

    attrs =
      attrs
      |> Map.put("service_user_id", su.id)
      |> Map.put("service_date", date_str)

    case Plans.create_attendance_record(socket.assigns.current_scope, attrs) do
      {:ok, _record} ->
        sheet = Plans.build_attendance_sheet(su.id, socket.assigns.year, socket.assigns.month)

        {:noreply,
         socket
         |> put_flash(:info, gettext("%{d} の記録を保存しました", d: date_str))
         |> assign(:sheet, sheet)}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, first_error_message(changeset))}
    end
  end

  # --- helpers ---

  defp parse_year_month(params) do
    today = Date.utc_today()
    year = parse_int(params["year"], today.year)
    month = parse_int(params["month"], today.month)
    if month in 1..12, do: {year, month}, else: {today.year, today.month}
  end

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> default
    end
  end

  defp parse_int(_, default), do: default

  defp prev_month(year, 1), do: {year - 1, 12}
  defp prev_month(year, month), do: {year, month - 1}
  defp next_month(year, 12), do: {year + 1, 1}
  defp next_month(year, month), do: {year, month + 1}

  defp month_path(service_user, {year, month}) do
    ~p"/service_users/#{service_user.id}/attendance?#{[year: year, month: month]}"
  end

  # Sunday=1 … Saturday=7
  defp weekday_label(%Date{} = d) do
    elem({"日", "月", "火", "水", "木", "金", "土"}, Date.day_of_week(d, :sunday) - 1)
  end

  defp row_class(%Date{} = d) do
    case Date.day_of_week(d, :sunday) do
      1 -> "bg-base-200/50"
      7 -> "bg-base-200/50"
      _ -> ""
    end
  end

  defp selected_provision?(%{record: nil}, value), do: value == ""

  defp selected_provision?(%{record: rec}, value),
    do: to_string(rec.provision_type) == to_string(value)

  defp checked?(%{record: nil}, _field), do: false
  defp checked?(%{record: rec}, field), do: Map.get(rec, field) == true

  defp time_value(%{record: nil}, _field), do: ""

  defp time_value(%{record: rec}, field) do
    case Map.get(rec, field) do
      %Time{} = t -> Time.to_iso8601(t)
      _ -> ""
    end
  end

  defp note_value(%{record: nil}), do: ""
  defp note_value(%{record: rec}), do: rec.note || ""

  defp first_error_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.flat_map(fn {field, msgs} -> Enum.map(msgs, &"#{field} #{&1}") end)
    |> List.first()
    |> Kernel.||(gettext("保存できませんでした"))
  end
end
