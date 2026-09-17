defmodule Ayumi.Imports.AttendancePlan do
  @moduledoc """
  Plans an attendance import: which rows would be appended as new, which as
  corrections, which are unchanged, and which are in error. Reads the database
  but never writes.
  """

  alias Ayumi.CSV.Attendance
  alias Ayumi.Imports.Matching
  alias Ayumi.Imports.Preview
  alias Ayumi.Plans
  alias Ayumi.Plans.AttendanceRecord

  @doc "Builds the preview for decoded `rows` (`[{row_number, cells}]`)."
  def build(rows, ignored_headers) do
    directory = service_user_directory()
    results = Enum.map(rows, &plan_row(&1, directory))

    {candidates, duplicate_errors} =
      reject_duplicates(for {:ok, candidate} <- results, do: candidate)

    row_errors = for {:error, errors} <- results, error <- errors, do: error
    {to_insert, unchanged} = classify(candidates, current_attendance(candidates))

    %Preview{
      dataset: :attendance,
      total_rows: length(rows),
      rows: rows,
      to_insert: to_insert,
      unchanged: unchanged,
      errors: Enum.sort_by(row_errors ++ duplicate_errors, & &1.row),
      ignored_headers: ignored_headers
    }
  end

  defp plan_row({row, cells}, directory) do
    with {:ok, parsed} <- Attendance.parse(cells),
         {:ok, service_user} <- resolve_service_user(parsed, directory),
         attrs = attendance_attrs(parsed, service_user),
         :ok <- validate(attrs) do
      {:ok, %{row: row, attrs: attrs}}
    else
      {:error, errors} -> {:error, Enum.map(errors, &Map.put(&1, :row, row))}
    end
  end

  defp attendance_attrs(parsed, service_user) do
    parsed
    |> Map.drop([:service_user_name])
    |> Map.put(:service_user_id, service_user.id)
  end

  # Validation stays in the changeset; this only maps its errors onto columns.
  defp validate(attrs) do
    changeset = Plans.change_attendance_record(%AttendanceRecord{}, attrs)

    if changeset.valid?,
      do: :ok,
      else: {:error, Ayumi.Imports.changeset_errors(changeset, &Attendance.header_for/1)}
  end

  # A service user and date may appear once per file. A repeat is an error rather
  # than last-wins: it is more likely a copy-paste slip than an intended correction.
  defp reject_duplicates(candidates) do
    {kept, errors, _seen} =
      Enum.reduce(candidates, {[], [], %{}}, fn candidate, {kept, errors, seen} ->
        key = attendance_key(candidate.attrs)

        case seen do
          %{^key => first_row} ->
            {kept, [duplicate_error(candidate.row, first_row) | errors], seen}

          _ ->
            {[candidate | kept], errors, Map.put(seen, key, candidate.row)}
        end
      end)

    {Enum.reverse(kept), errors}
  end

  defp duplicate_error(row, first_row) do
    %{
      row: row,
      column: Attendance.header_for(:service_date),
      message: "#{first_row}行目と同じ利用者・利用日です。1 つにまとめてください"
    }
  end

  defp attendance_key(attrs), do: {attrs.service_user_id, attrs.service_date}

  defp current_attendance([]), do: %{}

  defp current_attendance(candidates) do
    dates = Enum.map(candidates, & &1.attrs.service_date)

    dates
    |> Enum.min(Date)
    |> Plans.list_attendance_records_between(Enum.max(dates, Date))
    |> Plans.latest_attendance_by_user_date()
  end

  defp classify(candidates, latest) do
    classified = Enum.map(candidates, &{classify_one(&1, latest), &1})

    to_insert =
      for {kind, candidate} <- classified, kind != :unchanged, do: Map.put(candidate, :kind, kind)

    unchanged = for {:unchanged, candidate} <- classified, do: candidate.row

    {to_insert, unchanged}
  end

  defp classify_one(candidate, latest) do
    case Map.get(latest, attendance_key(candidate.attrs)) do
      nil -> :new
      current -> if same_attendance?(current, candidate.attrs), do: :unchanged, else: :correction
    end
  end

  defp same_attendance?(current, attrs), do: comparable(current) == comparable(attrs)

  defp comparable(attendance) do
    {attendance.provision_type, attendance.pickup, attendance.dropoff, attendance.start_time,
     attendance.end_time, comparable_note(attendance.note)}
  end

  defp comparable_note(nil), do: ""
  defp comparable_note(note), do: note |> String.replace("\r\n", "\n") |> String.trim_trailing()

  ## Resolving service users

  # `利用者ID` is authoritative. `氏名` alone is accepted only when it is unique,
  # and when both are given they must agree — a guard against a pasted id column
  # that has slipped by a row. Withdrawn service users are included.
  defp service_user_directory do
    service_users = Plans.list_service_users(include_withdrawn: true)

    %{
      by_id: Map.new(service_users, &{&1.id, &1}),
      by_name: Enum.group_by(service_users, &Matching.name_key(&1.name))
    }
  end

  defp resolve_service_user(%{service_user_id: nil, service_user_name: nil}, _directory) do
    service_user_error(:service_user_id, "利用者ID か氏名を入力してください")
  end

  defp resolve_service_user(%{service_user_id: nil, service_user_name: name}, directory) do
    case Map.get(directory.by_name, Matching.name_key(name), []) do
      [service_user] ->
        {:ok, service_user}

      [] ->
        service_user_error(:service_user_name, "氏名「#{name}」の利用者が見つかりません")

      _several ->
        service_user_error(
          :service_user_name,
          "氏名「#{name}」の利用者が複数います。利用者ID を入力してください"
        )
    end
  end

  defp resolve_service_user(%{service_user_id: id, service_user_name: name}, directory) do
    case Map.get(directory.by_id, id) do
      nil -> service_user_error(:service_user_id, "利用者ID #{id} は登録されていません")
      service_user -> check_name(service_user, name)
    end
  end

  defp check_name(service_user, nil), do: {:ok, service_user}

  defp check_name(service_user, name) do
    if Matching.name_key(service_user.name) == Matching.name_key(name) do
      {:ok, service_user}
    else
      service_user_error(
        :service_user_name,
        "利用者ID #{service_user.id} の氏名は「#{service_user.name}」です。ID か氏名を確認してください"
      )
    end
  end

  defp service_user_error(key, message) do
    {:error, [%{column: Attendance.header_for(key), message: message}]}
  end
end
