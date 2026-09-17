defmodule Ayumi.Imports do
  @moduledoc """
  The Imports context: brings CSV files made in Excel into the app.

  An import is two steps. `preview_*` parses and validates the whole file and
  plans what would be written, without writing. `commit_*` re-plans inside a
  transaction and writes only if the plan still matches what was confirmed.

  Rules:

    * Append-only. Rows are inserted through the normal context functions. For
      attendance, an existing date gets a correction row and history is kept; for
      support records, a row that differs from every existing record is a new
      record; for the service user master, an already registered person is
      skipped, never updated. Removing a row from the CSV deletes nothing.
    * All or nothing. Any row error blocks the whole file.
    * Manager only, checked here as well as at the route.

  The planning itself lives in `Ayumi.Imports.AttendancePlan`,
  `Ayumi.Imports.SupportRecordsPlan`, and `Ayumi.Imports.ServiceUsersPlan`.
  """

  alias Ayumi.Accounts.Scope
  alias Ayumi.CSV
  alias Ayumi.Imports.AttendancePlan
  alias Ayumi.Imports.Preview
  alias Ayumi.Imports.ServiceUsersPlan
  alias Ayumi.Imports.SupportRecordsPlan
  alias Ayumi.Plans
  alias Ayumi.Repo

  @max_bytes 2_000_000
  # One month of attendance for every service user is about 1,100 rows. The cap
  # keeps the commit transaction well inside SQLite's busy timeout.
  @max_rows 5_000

  @doc "Largest accepted file, in bytes."
  def max_bytes, do: @max_bytes

  @doc "Largest accepted number of data rows."
  def max_rows, do: @max_rows

  ## By dataset (see `Ayumi.Imports.Dataset`)

  @doc "Plans an import of `dataset`. See `preview_attendance/2` for the return shape."
  def preview(%Scope{} = scope, :attendance, binary), do: preview_attendance(scope, binary)
  def preview(%Scope{} = scope, :service_users, binary), do: preview_service_users(scope, binary)

  def preview(%Scope{} = scope, :support_records, binary),
    do: preview_support_records(scope, binary)

  @doc "Writes a confirmed preview of any dataset. See `commit_attendance/2`."
  def commit(%Scope{} = scope, %Preview{dataset: :attendance} = preview),
    do: commit_attendance(scope, preview)

  def commit(%Scope{} = scope, %Preview{dataset: :service_users} = preview),
    do: commit_service_users(scope, preview)

  def commit(%Scope{} = scope, %Preview{dataset: :support_records} = preview),
    do: commit_support_records(scope, preview)

  ## Attendance

  @doc """
  Plans an attendance import. Returns `{:ok, %Preview{}}` — which may hold row
  errors — or `{:error, message}` when the file as a whole cannot be used.
  """
  def preview_attendance(%Scope{} = scope, binary) when is_binary(binary) do
    plan(scope, binary, CSV.Attendance, &AttendancePlan.build/2)
  end

  @doc """
  Writes a confirmed attendance preview. Returns `{:ok, counts}`,
  `{:error, :stale, fresh_preview}` when the data changed since the preview (so
  the plan must be confirmed again), or `{:error, message}`.
  """
  def commit_attendance(%Scope{} = scope, %Preview{dataset: :attendance} = preview) do
    write(scope, preview, &AttendancePlan.build/2, &Plans.create_attendance_record(scope, &1))
  end

  ## Support records

  @doc """
  Plans a support record import (see `Ayumi.Imports.SupportRecordsPlan`). Same
  return shape as `preview_attendance/2`.
  """
  def preview_support_records(%Scope{} = scope, binary) when is_binary(binary) do
    plan(scope, binary, CSV.SupportRecords, &SupportRecordsPlan.build(scope, &1, &2))
  end

  @doc "Writes a confirmed support record preview. Same return shape as `commit_attendance/2`."
  def commit_support_records(%Scope{} = scope, %Preview{dataset: :support_records} = preview) do
    write(
      scope,
      preview,
      &SupportRecordsPlan.build(scope, &1, &2),
      &Plans.create_support_record(scope, &1)
    )
  end

  ## Service user master

  @doc """
  Plans a service user master import (create-only; see
  `Ayumi.Imports.ServiceUsersPlan`). Same return shape as `preview_attendance/2`.
  """
  def preview_service_users(%Scope{} = scope, binary) when is_binary(binary) do
    plan(scope, binary, CSV.ServiceUsers, &ServiceUsersPlan.build/2)
  end

  @doc "Writes a confirmed service user preview. Same return shape as `commit_attendance/2`."
  def commit_service_users(%Scope{} = scope, %Preview{dataset: :service_users} = preview) do
    write(scope, preview, &ServiceUsersPlan.build/2, &Plans.create_service_user/1)
  end

  ## Shared steps

  defp plan(scope, binary, layout, build) do
    with :ok <- authorize(scope),
         :ok <- check_size(binary),
         {:ok, decoded} <- CSV.decode(binary),
         :ok <- check_headers(decoded.headers, layout.required_headers()),
         :ok <- check_row_count(decoded.rows) do
      {:ok, build.(decoded.rows, decoded.headers -- layout.headers())}
    end
  end

  defp write(scope, preview, build, insert) do
    with :ok <- authorize(scope),
         :ok <- check_no_errors(preview) do
      fn -> commit_in_transaction(preview, build, insert) end
      |> Repo.transaction()
      |> case do
        {:ok, counts} -> {:ok, counts}
        {:error, {:stale, fresh}} -> {:error, :stale, fresh}
        {:error, message} -> {:error, message}
      end
    end
  end

  defp commit_in_transaction(preview, build, insert) do
    fresh = build.(preview.rows, preview.ignored_headers)

    if fresh.errors != [] or fresh.to_insert != preview.to_insert,
      do: Repo.rollback({:stale, fresh})

    Enum.each(fresh.to_insert, &insert_row(&1, insert))

    counts = Preview.counts(fresh)

    %{
      inserted: counts.new + counts.corrections,
      corrections: counts.corrections,
      unchanged: counts.unchanged,
      skipped: counts.skipped
    }
  end

  defp insert_row(%{row: row, attrs: attrs}, insert) do
    case insert.(attrs) do
      {:ok, _record} -> :ok
      {:error, _changeset} -> Repo.rollback("#{row}行目を登録できませんでした。取込を中止しました。")
    end
  end

  @doc false
  # Maps changeset errors onto CSV columns for the planners. The app's own
  # validation messages are Japanese; Ecto's built-in ones are English (there is
  # no ja locale), so those are replaced with a generic message — the cell parsers
  # catch blank and malformed cells before a changeset ever sees them.
  def changeset_errors(%Ecto.Changeset{} = changeset, header_for) do
    for {field, {message, _opts}} <- changeset.errors do
      %{column: header_for.(field), message: localize(message)}
    end
  end

  defp localize(message) do
    if message =~ ~r/[^\x00-\x7F]/, do: message, else: "値が正しくありません"
  end

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
      [] ->
        :ok

      missing ->
        {:error, "必要な列がありません: #{Enum.join(missing, "、")}。CSV出力したファイルの見出しをそのまま使ってください。"}
    end
  end

  defp check_row_count(rows) do
    if length(rows) <= @max_rows,
      do: :ok,
      else: {:error, "行数が多すぎます（上限 #{@max_rows} 行）。月ごとに分けて取り込んでください。"}
  end

  defp check_no_errors(%Preview{errors: []}), do: :ok

  defp check_no_errors(%Preview{}) do
    {:error, "エラーのある行があるため取り込めません。CSV を修正してもう一度選択してください。"}
  end
end
