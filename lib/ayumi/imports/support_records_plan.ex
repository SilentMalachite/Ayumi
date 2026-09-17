defmodule Ayumi.Imports.SupportRecordsPlan do
  @moduledoc """
  Plans a support record import. Reads the database but never writes.

  A support record has no natural key — several notes for one person on one day
  are normal — so there is no "correction" here. A row identical to an existing
  record (same service user, support date, category, and content) is unchanged and
  skipped, which makes re-importing a file, or importing an exported one, a no-op.
  Any other row is a new record. Editing an exported row and importing it therefore
  adds a record next to the original; when the row's 記録ID shows that this is
  what happened, the preview warns about it.

  Rows are validated with `Plans.support_record_changeset/2`, the changeset the
  write itself uses, so the future-date and withdrawn-user rules apply in the
  preview exactly as they will at commit.
  """

  alias Ayumi.Accounts.Scope
  alias Ayumi.CSV.SupportRecords
  alias Ayumi.Imports.Preview
  alias Ayumi.Imports.ServiceUserResolver
  alias Ayumi.Plans

  @doc "Builds the preview for decoded `rows` (`[{row_number, cells}]`)."
  def build(%Scope{} = scope, rows, ignored_headers) do
    directory = ServiceUserResolver.directory()
    results = Enum.map(rows, &plan_row(&1, scope, directory))

    {candidates, duplicate_errors} =
      reject_duplicates(for {:ok, candidate} <- results, do: candidate)

    row_errors = for {:error, errors} <- results, error <- errors, do: error
    existing = existing_keys(candidates)
    {unchanged, to_insert} = Enum.split_with(candidates, &MapSet.member?(existing, key(&1.attrs)))

    %Preview{
      dataset: :support_records,
      total_rows: length(rows),
      rows: rows,
      to_insert: Enum.map(to_insert, &%{row: &1.row, kind: :new, attrs: &1.attrs}),
      unchanged: Enum.map(unchanged, & &1.row),
      errors: Enum.sort_by(row_errors ++ duplicate_errors, & &1.row),
      warnings: edited_export_warnings(to_insert),
      ignored_headers: ignored_headers
    }
  end

  defp plan_row({row, cells}, scope, directory) do
    with {:ok, parsed} <- SupportRecords.parse(cells),
         {:ok, service_user} <-
           ServiceUserResolver.resolve(parsed, directory, &SupportRecords.header_for/1),
         attrs = insert_attrs(parsed, service_user),
         :ok <- validate(scope, attrs) do
      {:ok, %{row: row, attrs: attrs, record_id: parsed.record_id}}
    else
      {:error, errors} -> {:error, Enum.map(errors, &Map.put(&1, :row, row))}
    end
  end

  defp insert_attrs(parsed, service_user) do
    parsed
    |> Map.take([:support_date, :category, :content])
    |> Map.put(:service_user_id, service_user.id)
  end

  # Validation stays in the changeset; this only maps its errors onto columns.
  defp validate(scope, attrs) do
    changeset = Plans.support_record_changeset(scope, attrs)

    if changeset.valid?,
      do: :ok,
      else: {:error, Ayumi.Imports.changeset_errors(changeset, &SupportRecords.header_for/1)}
  end

  # What makes two support records "the same". Content is compared ignoring
  # line-ending style and trailing whitespace, which Excel changes freely.
  defp key(record) do
    {record.service_user_id, record.support_date, record.category, content_key(record.content)}
  end

  defp content_key(content), do: content |> String.replace("\r\n", "\n") |> String.trim_trailing()

  defp reject_duplicates(candidates) do
    {kept, errors, _seen} =
      Enum.reduce(candidates, {[], [], %{}}, fn candidate, {kept, errors, seen} ->
        key = key(candidate.attrs)

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
      column: SupportRecords.header_for(:content),
      message: "#{first_row}行目と同じ利用者・支援日・区分・内容です。1 つにまとめてください"
    }
  end

  defp existing_keys([]), do: MapSet.new()

  defp existing_keys(candidates) do
    dates = Enum.map(candidates, & &1.attrs.support_date)

    dates
    |> Enum.min(Date)
    |> Plans.list_support_records_between(Enum.max(dates, Date))
    |> MapSet.new(&key/1)
  end

  # A new row that carries the 記録ID of an existing record came from an export
  # and was edited. Importing it cannot change that record (append-only), so say so.
  defp edited_export_warnings(to_insert) do
    known_ids =
      to_insert
      |> Enum.map(& &1.record_id)
      |> Enum.reject(&is_nil/1)
      |> Plans.get_support_records()
      |> MapSet.new(& &1.id)

    for candidate <- to_insert, MapSet.member?(known_ids, candidate.record_id) do
      %{
        row: candidate.row,
        column: SupportRecords.header_for(:record_id),
        message:
          "記録ID #{candidate.record_id} の記録と内容が異なります。元の記録は残り、" <>
            "この行は新しい記録として追加されます"
      }
    end
  end
end
