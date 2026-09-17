defmodule Ayumi.Imports do
  @moduledoc """
  The Imports context: brings CSV files made in Excel into the append-only logs.

  An import is two steps. `preview_*` parses and validates the whole file and
  plans what would be written, without writing. `commit_*` re-plans inside a
  transaction and writes only if the plan still matches what was confirmed.

  Rules:

    * Append-only. Rows are inserted through the normal context functions, so an
      existing date gets a correction row and history is kept. Removing a row
      from the CSV deletes nothing.
    * All or nothing. Any row error blocks the whole file.
    * Manager only, checked here as well as at the route.
  """

  alias Ayumi.Accounts.Scope
  alias Ayumi.CSV
  alias Ayumi.CSV.Attendance
  alias Ayumi.Imports.Preview
  alias Ayumi.Plans
  alias Ayumi.Plans.AttendanceRecord
  alias Ayumi.Repo

  @max_bytes 2_000_000
  # One month for every service user is about 1,100 rows. The cap keeps the
  # commit transaction well inside SQLite's busy timeout.
  @max_rows 5_000

  @doc "Largest accepted file, in bytes."
  def max_bytes, do: @max_bytes

  @doc "Largest accepted number of data rows."
  def max_rows, do: @max_rows

  ## Attendance

  @doc """
  Plans an attendance import. Returns `{:ok, %Preview{}}` — which may hold row
  errors — or `{:error, message}` when the file as a whole cannot be used.
  """
  def preview_attendance(%Scope{} = scope, binary) when is_binary(binary) do
    with :ok <- authorize(scope),
         :ok <- check_size(binary),
         {:ok, decoded} <- CSV.decode(binary),
         :ok <- check_headers(decoded.headers, Attendance.required_headers()),
         :ok <- check_row_count(decoded.rows) do
      {:ok, plan_attendance(decoded.rows, decoded.headers -- Attendance.headers())}
    end
  end

  @doc """
  Writes a confirmed attendance preview. Returns `{:ok, counts}`,
  `{:error, :stale, fresh_preview}` when the data changed since the preview (so
  the plan must be confirmed again), or `{:error, message}`.
  """
  def commit_attendance(%Scope{} = scope, %Preview{} = preview) do
    with :ok <- authorize(scope),
         :ok <- check_no_errors(preview) do
      fn -> commit_attendance_in_transaction(scope, preview) end
      |> Repo.transaction()
      |> case do
        {:ok, counts} -> {:ok, counts}
        {:error, {:stale, fresh}} -> {:error, :stale, fresh}
        {:error, message} -> {:error, message}
      end
    end
  end

  defp commit_attendance_in_transaction(scope, preview) do
    fresh = plan_attendance(preview.rows, preview.ignored_headers)

    if fresh.errors != [] or fresh.to_insert != preview.to_insert,
      do: Repo.rollback({:stale, fresh})

    Enum.each(fresh.to_insert, &insert_attendance(scope, &1))

    counts = Preview.counts(fresh)

    %{
      inserted: counts.new + counts.corrections,
      corrections: counts.corrections,
      unchanged: counts.unchanged
    }
  end

  defp insert_attendance(scope, %{row: row, attrs: attrs}) do
    case Plans.create_attendance_record(scope, attrs) do
      {:ok, _record} -> :ok
      {:error, _changeset} -> Repo.rollback("#{row}行目を登録できませんでした。取込を中止しました。")
    end
  end

  defp plan_attendance(rows, ignored_headers) do
    directory = service_user_directory()
    results = Enum.map(rows, &plan_attendance_row(&1, directory))

    {candidates, duplicate_errors} =
      reject_duplicates(for {:ok, candidate} <- results, do: candidate)

    row_errors = for {:error, errors} <- results, error <- errors, do: error
    latest = current_attendance(candidates)
    {to_insert, unchanged} = classify(candidates, latest)

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

  defp plan_attendance_row({row, cells}, directory) do
    with {:ok, parsed} <- Attendance.parse(cells),
         {:ok, service_user} <- resolve_service_user(parsed, directory),
         attrs = attendance_attrs(parsed, service_user),
         :ok <- validate_attendance(attrs) do
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
  defp validate_attendance(attrs) do
    changeset = Plans.change_attendance_record(%AttendanceRecord{}, attrs)

    if changeset.valid? do
      :ok
    else
      {:error,
       for {field, {message, _opts}} <- changeset.errors do
         %{column: Attendance.header_for(field), message: localize(message)}
       end}
    end
  end

  # The app's own validation messages are Japanese. Ecto's built-in ones are
  # English (there is no ja locale), so they are replaced with a generic message;
  # the cell parsers catch blank and malformed cells before this point anyway.
  defp localize(message) do
    if String.printable?(message) and message =~ ~r/[^\x00-\x7F]/,
      do: message,
      else: "値が正しくありません"
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

  defp same_attendance?(current, attrs) do
    comparable(current) == comparable(attrs)
  end

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
      by_name: Enum.group_by(service_users, &name_key(&1.name))
    }
  end

  defp resolve_service_user(%{service_user_id: nil, service_user_name: nil}, _directory) do
    service_user_error(:service_user_id, "利用者ID か氏名を入力してください")
  end

  defp resolve_service_user(%{service_user_id: nil, service_user_name: name}, directory) do
    case Map.get(directory.by_name, name_key(name), []) do
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
      nil ->
        service_user_error(:service_user_id, "利用者ID #{id} は登録されていません")

      service_user ->
        check_name(service_user, name)
    end
  end

  defp check_name(service_user, nil), do: {:ok, service_user}

  defp check_name(service_user, name) do
    if name_key(service_user.name) == name_key(name) do
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

  # Names are compared ignoring width and spacing: 「山田　太郎」 equals 「山田 太郎」.
  defp name_key(name), do: name |> String.normalize(:nfkc) |> String.replace(~r/\s/u, "")

  ## File-level checks

  defp authorize(%Scope{} = scope) do
    if Scope.manager?(scope),
      do: :ok,
      else: {:error, "CSV の取込にはサービス管理責任者の権限が必要です。"}
  end

  defp check_size(binary) do
    if byte_size(binary) <= @max_bytes,
      do: :ok,
      else: {:error, "ファイルが大きすぎます（上限 #{div(@max_bytes, 1_000_000)} MB）。月ごとに分けて取り込んでください。"}
  end

  defp check_headers(headers, required) do
    case required -- headers do
      [] -> :ok
      missing -> {:error, "必要な列がありません: #{Enum.join(missing, "、")}。CSV出力したファイルの見出しをそのまま使ってください。"}
    end
  end

  defp check_row_count(rows) do
    if length(rows) <= @max_rows,
      do: :ok,
      else: {:error, "行数が多すぎます（上限 #{@max_rows} 行）。月ごとに分けて取り込んでください。"}
  end

  defp check_no_errors(%Preview{errors: []}), do: :ok
  defp check_no_errors(%Preview{}), do: {:error, "エラーのある行があるため取り込めません。CSV を修正してもう一度選択してください。"}
end
