defmodule Ayumi.Exports do
  @moduledoc """
  The Exports context: turns recorded data into CSV files for Excel.

  Exports are derived on demand and never stored. Withdrawn service users are
  always included — an export is a record of what happened, not a working list.
  """

  alias Ayumi.Accounts.Scope
  alias Ayumi.CSV
  alias Ayumi.Exports.Dataset
  alias Ayumi.Exports.Period
  alias Ayumi.Exports.Request
  alias Ayumi.JST
  alias Ayumi.Plans

  @doc """
  Returns a changeset for the export form. Without attrs it holds the defaults:
  this month's attendance for every service user.
  """
  def change_request(attrs \\ nil)

  def change_request(nil), do: Request.changeset(default_request(), %{})

  def change_request(attrs) when is_map(attrs) do
    default_request()
    |> Request.changeset(attrs)
    |> Map.put(:action, :validate)
  end

  defp default_request do
    %Request{dataset: :attendance, unit: :month, anchor_date: JST.today()}
  end

  @doc "Whether the request's dataset is exported for a period (false for master lists)."
  def periodic?(%Ecto.Changeset{} = changeset) do
    changeset |> Ecto.Changeset.get_field(:dataset) |> Dataset.periodic?()
  end

  @doc """
  Describes the period a request covers; nil while the request is invalid or when
  its dataset has no period.
  """
  def period_label(%Ecto.Changeset{valid?: false}), do: nil

  def period_label(%Ecto.Changeset{} = changeset) do
    request = Ecto.Changeset.apply_changes(changeset)

    if Dataset.periodic?(request.dataset),
      do: Period.label(request.unit, request.anchor_date)
  end

  @doc "The request as string params for the download URL; nil while invalid."
  def request_params(%Ecto.Changeset{valid?: false}), do: nil

  def request_params(%Ecto.Changeset{} = changeset) do
    request = Ecto.Changeset.apply_changes(changeset)
    params = %{"dataset" => Atom.to_string(request.dataset)}

    if Dataset.periodic?(request.dataset),
      do: Map.merge(params, period_params(request)),
      else: params
  end

  defp period_params(%Request{} = request) do
    params = %{
      "unit" => Atom.to_string(request.unit),
      "anchor_date" => Date.to_iso8601(request.anchor_date)
    }

    case request.service_user_id do
      nil -> params
      id -> Map.put(params, "service_user_id", Integer.to_string(id))
    end
  end

  @doc """
  Builds the CSV file described by `params` (see `Ayumi.Exports.Request`).
  Any authenticated staff member may export.
  """
  def build(%Scope{}, params) when is_map(params) do
    changeset = Request.changeset(%Request{}, params)

    with {:ok, request} <- Ecto.Changeset.apply_action(changeset, :validate) do
      {:ok, %{filename: filename(request), content: content(request)}}
    end
  end

  defp content(%Request{dataset: :attendance} = request) do
    {from, to} = Period.range(request.unit, request.anchor_date)

    records =
      from
      |> Plans.list_attendance_records_between(to, service_user_id: request.service_user_id)
      |> Plans.latest_attendance_by_user_date()
      |> Map.values()
      |> Enum.sort_by(&attendance_sort_key/1)

    CSV.encode(CSV.Attendance.headers(), CSV.Attendance.dump(records))
  end

  defp content(%Request{dataset: :support_records} = request) do
    records = list_log(request, &Plans.list_support_records_between/3)
    CSV.encode(CSV.SupportRecords.headers(), CSV.SupportRecords.dump(records))
  end

  defp content(%Request{dataset: :goal_progress} = request) do
    rows = list_log(request, &Plans.list_goal_progress_between/3)
    CSV.encode(CSV.GoalProgress.headers(), CSV.GoalProgress.dump(rows))
  end

  defp content(%Request{dataset: :plan_phase_events} = request) do
    rows = list_log(request, &Plans.list_plan_phase_events_between/3)
    CSV.encode(CSV.PlanPhaseEvents.headers(), CSV.PlanPhaseEvents.dump(rows))
  end

  defp content(%Request{dataset: :service_users}) do
    service_users =
      Plans.list_service_users(include_withdrawn: true, preload: [:disability_certificates])

    CSV.encode(CSV.ServiceUsers.headers(), CSV.ServiceUsers.dump(service_users))
  end

  # The logs are stamped in UTC, but a "month" on the form means a month on the
  # Japanese calendar, so the period is converted to a UTC range here. Plans
  # stays time zone agnostic.
  defp list_log(%Request{} = request, list_between) do
    {from_date, to_date} = Period.range(request.unit, request.anchor_date)
    {from, to} = JST.utc_range(from_date, to_date)

    list_between.(from, to, service_user_id: request.service_user_id)
  end

  # Same order as Plans.list_service_users/1 (kana, then name), then by date.
  defp attendance_sort_key(record) do
    service_user = record.service_user

    {service_user.name_kana || "", service_user.name, service_user.id,
     Date.to_erl(record.service_date)}
  end

  defp filename(%Request{} = request) do
    request
    |> filename_parts()
    |> Enum.filter(& &1)
    |> Enum.join("_")
    |> Kernel.<>(".csv")
  end

  defp filename_parts(%Request{} = request) do
    if Dataset.periodic?(request.dataset) do
      [
        Dataset.file_label(request.dataset),
        Period.filename_part(request.unit, request.anchor_date),
        request.service_user_id && "利用者#{request.service_user_id}"
      ]
    else
      # A master list is a snapshot, so the file is named after the export date.
      [Dataset.file_label(request.dataset), Date.to_iso8601(JST.today())]
    end
  end
end
