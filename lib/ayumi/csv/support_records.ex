defmodule Ayumi.CSV.SupportRecords do
  @moduledoc """
  CSV layout for support records (支援記録).
  Records must have `:service_user` and `:recorded_by` preloaded.

  The import reads the support itself (利用者ID, 氏名, 支援日, 区分, 内容) and ignores
  the derived and audit columns. 記録ID is read when present — it lets the importer
  notice that a row came from an export and was edited — but a hand-made file may
  leave the column out.
  """

  alias Ayumi.Accounts.User
  alias Ayumi.CSV.Cell
  alias Ayumi.CSV.Columns
  alias Ayumi.Plans.EnrollmentStatus
  alias Ayumi.Plans.SupportRecordCategory

  @doc "The header row."
  def headers, do: Columns.headers(columns())

  @doc "Renders records as rows of cells aligned with `headers/0`."
  def dump(records), do: Columns.dump(columns(), records)

  @doc "Headers a file must contain."
  def required_headers, do: Columns.required_headers(columns())

  @doc "Parses one row's cells into attrs, or returns every cell error at once."
  def parse(cells), do: Columns.parse_row(columns(), cells)

  @doc "The header of the column stored under an attrs key; nil when there is none."
  def header_for(key), do: Columns.header_for(columns(), key)

  defp columns do
    [
      {"利用者ID", &Cell.format_id(&1.service_user_id),
       key: :service_user_id, parse: &Cell.parse_id/1},
      {"氏名", &Cell.format_text(&1.service_user.name),
       key: :service_user_name, parse: &Cell.parse_text/1},
      {"在籍状態", &Cell.format_enum(&1.service_user.enrollment_status, EnrollmentStatus)},
      {"支援日", &Cell.format_date(&1.support_date),
       key: :support_date, parse: &Cell.parse_date/1, required: true},
      {"区分", &Cell.format_enum(&1.category, SupportRecordCategory),
       key: :category, parse: &Cell.parse_enum(&1, SupportRecordCategory), required: true},
      {"内容", &Cell.format_text(&1.content),
       key: :content, parse: &Cell.parse_text/1, required: true},
      {"記録者", &User.display_name(&1.recorded_by)},
      {"記録日時(日本時間)", &Cell.format_datetime(&1.recorded_at)},
      {"記録ID", &Cell.format_id(&1.id),
       key: :record_id, parse: &Cell.parse_id/1, optional_header: true}
    ]
  end
end
