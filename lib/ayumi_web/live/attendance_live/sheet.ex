defmodule AyumiWeb.AttendanceLive.Sheet do
  @moduledoc "利用者別・1か月分の実績記録票 (印刷向けHTML)。"
  use AyumiWeb, :live_view

  alias Ayumi.Plans
  alias Ayumi.Plans.ProvisionType
  alias AyumiWeb.AttendanceLive.MonthParams

  @impl true
  def mount(%{"service_user_id" => id}, _session, socket) do
    {:ok, assign(socket, :service_user, Plans.get_service_user!(id))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {year, month} = MonthParams.parse(params)
    sheet = Plans.build_attendance_sheet(socket.assigns.service_user.id, year, month)

    {:noreply,
     socket
     |> assign(:year, year)
     |> assign(:month, month)
     |> assign(:sheet, sheet)
     |> assign(:facility, facility_info())
     |> assign(:page_title, gettext("実績記録票 %{y}年%{m}月", y: year, m: month))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- 印刷時の用紙サイズ・余白。Tailwind では @page を表現できないためここに置く。 --%>
      <style>
        @page { size: A4; margin: 12mm; }
      </style>

      <div class="print:hidden mb-3 flex gap-2">
        <button type="button" onclick="window.print()" class="btn btn-primary btn-sm">
          {gettext("印刷")}
        </button>
        <.link
          patch={~p"/service_users/#{@service_user.id}/attendance/sheet?#{[year: prev_year(@year, @month), month: prev_month(@year, @month)]}"}
          class="btn btn-ghost btn-sm"
        >
          {gettext("← 前月")}
        </.link>
        <.link
          patch={~p"/service_users/#{@service_user.id}/attendance/sheet?#{[year: next_year(@year, @month), month: next_month(@year, @month)]}"}
          class="btn btn-ghost btn-sm"
        >
          {gettext("翌月 →")}
        </.link>
        <.link
          navigate={~p"/service_users/#{@service_user.id}/attendance?#{[year: @year, month: @month]}"}
          class="btn btn-ghost btn-sm"
        >
          {gettext("入力画面へ戻る")}
        </.link>
      </div>

      <header class="mb-3 text-sm">
        <h1 class="text-lg font-bold border-b border-black">
          {gettext("サービス提供実績記録票")}
        </h1>
        <div class="grid grid-cols-2 gap-2 mt-2">
          <div>
            {gettext("事業所名")}:
            <span class="inline-block min-w-32 border-b border-black px-1">{@facility.name}</span>
          </div>
          <div>
            {gettext("事業所番号")}:
            <span class="inline-block min-w-32 border-b border-black px-1">{@facility.number}</span>
          </div>
          <div>
            {gettext("受給者証番号")}:
            <span class="inline-block min-w-32 border-b border-black px-1">{@service_user.recipient_cert_number}</span>
          </div>
          <div>
            {gettext("市町村")}:
            <span class="inline-block min-w-32 border-b border-black px-1">{@service_user.recipient_cert_municipality}</span>
          </div>
          <div class="col-span-2">
            {gettext("利用者氏名")}:
            <span class="inline-block min-w-48 border-b border-black px-1">{@service_user.name}</span>
            <span class="text-xs ml-2">({@service_user.name_kana})</span>
          </div>
          <div class="col-span-2">
            {gettext("対象年月")}: <strong>{gettext("%{y}年%{m}月", y: @year, m: @month)}</strong>
          </div>
        </div>
      </header>

      <table class="w-full text-xs border-collapse border border-black">
        <thead>
          <tr>
            <th class="border border-black px-1">{gettext("日")}</th>
            <th class="border border-black px-1">{gettext("曜")}</th>
            <th class="border border-black px-1">{gettext("提供形態")}</th>
            <th class="border border-black px-1">{gettext("開始")}</th>
            <th class="border border-black px-1">{gettext("終了")}</th>
            <th class="border border-black px-1">{gettext("送迎 往")}</th>
            <th class="border border-black px-1">{gettext("送迎 復")}</th>
            <th class="border border-black px-1">{gettext("欠席時対応")}</th>
            <th class="border border-black px-1">{gettext("備考")}</th>
            <th class="border border-black px-1">{gettext("利用者確認印")}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={line <- @sheet.lines} data-day={line.date.day} class={row_class(line.date)}>
            <td class="border border-black px-1 text-right">{line.date.day}</td>
            <td class="border border-black px-1">{weekday_label(line.date)}</td>
            <td class="border border-black px-1">{provision_label(line)}</td>
            <td class="border border-black px-1">{time_text(line, :start_time)}</td>
            <td class="border border-black px-1">{time_text(line, :end_time)}</td>
            <td class="border border-black px-1 text-center">{pickup_mark(line)}</td>
            <td class="border border-black px-1 text-center">{dropoff_mark(line)}</td>
            <td class="border border-black px-1 text-center">{absence_support_mark(line)}</td>
            <td class="border border-black px-1">{note_text(line)}</td>
            <td class="border border-black px-1"></td>
          </tr>
        </tbody>
      </table>

      <section class="mt-3 grid grid-cols-2 sm:grid-cols-5 gap-2 text-xs">
        <div class="border border-black px-2 py-1">{gettext("利用日数")}: <strong>{@sheet.totals.billable_days}</strong></div>
        <div class="border border-black px-2 py-1">{gettext("うち施設外")}: <strong>{@sheet.totals.offsite_days}</strong></div>
        <div class="border border-black px-2 py-1">{gettext("送迎 往")}: <strong>{@sheet.totals.pickup_count}</strong></div>
        <div class="border border-black px-2 py-1">{gettext("送迎 復")}: <strong>{@sheet.totals.dropoff_count}</strong></div>
        <div class="border border-black px-2 py-1">{gettext("欠席時対応")}: <strong>{@sheet.totals.absence_support_count}</strong></div>
      </section>
    </Layouts.app>
    """
  end

  # --- helpers ---

  # 事業所名・事業所番号は DB を増やさず application config から読む。
  # 未設定なら空文字 (= 手書き欄として印刷される)。
  defp facility_info do
    cfg = Application.get_env(:ayumi, :facility, [])
    %{name: Keyword.get(cfg, :name, ""), number: Keyword.get(cfg, :number, "")}
  end

  defp prev_month(_year, 1), do: 12
  defp prev_month(_year, month), do: month - 1
  defp prev_year(year, 1), do: year - 1
  defp prev_year(year, _month), do: year
  defp next_month(_year, 12), do: 1
  defp next_month(_year, month), do: month + 1
  defp next_year(year, 12), do: year + 1
  defp next_year(year, _month), do: year

  # Sunday=1 … Saturday=7 (Index と同じロジック)
  defp weekday_label(%Date{} = d) do
    elem({"日", "月", "火", "水", "木", "金", "土"}, Date.day_of_week(d, :sunday) - 1)
  end

  defp row_class(%Date{} = d) do
    # 白黒前提のため網掛けではなく罫線/空白のみ。土日もここでは強調しない。
    case Date.day_of_week(d, :sunday) do
      _ -> ""
    end
  end

  defp provision_label(%{record: nil}), do: ""
  defp provision_label(%{record: rec}), do: ProvisionType.label(rec.provision_type) || ""

  defp time_text(%{record: nil}, _field), do: ""

  defp time_text(%{record: rec}, field) do
    case Map.get(rec, field) do
      %Time{} = t -> Time.to_iso8601(t)
      _ -> ""
    end
  end

  defp pickup_mark(%{record: %{pickup: true}}), do: "○"
  defp pickup_mark(_), do: ""

  defp dropoff_mark(%{record: %{dropoff: true}}), do: "○"
  defp dropoff_mark(_), do: ""

  defp absence_support_mark(%{record: %{provision_type: :absence_support}}), do: "○"
  defp absence_support_mark(_), do: ""

  defp note_text(%{record: nil}), do: ""
  defp note_text(%{record: rec}), do: rec.note || ""

  # 将来 billable?/offsite? を行装飾に使うときのために残しておく (本タスクでは未使用)
  defp _billable?(type), do: type in ProvisionType.billable()
  defp _offsite?(type), do: type in ProvisionType.offsite()
end
