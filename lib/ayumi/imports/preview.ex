defmodule Ayumi.Imports.Preview do
  @moduledoc """
  What an import would do, computed without writing anything. Staff confirm the
  preview before it is committed.

    * `rows` — the decoded file, `[{row_number, cells}]`, kept so that commit can
      re-plan against the then-current data
    * `to_insert` — `[%{row:, kind: :new | :correction, attrs:}]`; a correction
      appends a row for a date that already has one (history is never lost)
    * `unchanged` — row numbers identical to the current state; skipped, so
      importing the same file twice does not bloat the log
    * `skipped` — `[%{row:, reason:}]`; rows for something that already exists
      and is deliberately left alone (the service user master never updates)
    * `errors` — `[%{row:, column:, message:}]`; any error blocks the whole import
    * `warnings` — `[%{row:, column:, message:}]`; worth a look, but not blocking
    * `ignored_headers` — columns in the file that the import does not know

  Row numbers are the ones Excel shows (the header is row 1).
  """

  defstruct dataset: nil,
            total_rows: 0,
            rows: [],
            to_insert: [],
            unchanged: [],
            skipped: [],
            errors: [],
            warnings: [],
            ignored_headers: []

  @doc "Counts for the confirmation screen."
  def counts(%__MODULE__{} = preview) do
    corrections = Enum.count(preview.to_insert, &(&1.kind == :correction))

    %{
      new: length(preview.to_insert) - corrections,
      corrections: corrections,
      unchanged: length(preview.unchanged),
      skipped: length(preview.skipped),
      errors: length(preview.errors),
      warnings: length(preview.warnings)
    }
  end
end
