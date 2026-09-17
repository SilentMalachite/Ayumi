defmodule Ayumi.CSV.Attendance do
  @moduledoc """
  CSV layout for attendance records (出欠・実績記録). Headers reuse the printed
  sheet's wording.

  The import reads the columns that describe the attendance itself and ignores
  the derived and audit columns (曜, 記録者, 記録日時, 記録ID), so an exported file
  can be edited in Excel and imported back. `parse/1` yields `:service_user_id`
  and `:service_user_name` as written; resolving them to a service user is the
  importer's job.

  Records must have `:service_user` and `:recorded_by` preloaded.
  """

  alias Ayumi.Accounts.User
  alias Ayumi.CSV.Cell
  alias Ayumi.CSV.Columns
  alias Ayumi.Plans.ProvisionType

  @doc "The header row."
  def headers, do: Columns.headers(columns())

  @doc "Renders records as rows of cells aligned with `headers/0`."
  def dump(records), do: Columns.dump(columns(), records)

  @doc "Headers the import reads. A file must contain all of them."
  def required_headers, do: Columns.required_headers(columns())

  @doc "Parses one row's cells into attrs, or returns every cell error at once."
  def parse(cells), do: Columns.parse_row(columns(), cells)

  @doc "The header of the column stored under an attrs key; nil when there is none."
  def header_for(key), do: Columns.header_for(columns(), key)

  # A function rather than a module attribute: anonymous functions cannot be
  # stored in attributes.
  defp columns do
    [
      {"利用者ID", &Cell.format_id(&1.service_user_id),
       key: :service_user_id, parse: &Cell.parse_id/1},
      {"氏名", &Cell.format_text(&1.service_user.name),
       key: :service_user_name, parse: &Cell.parse_text/1},
      {"利用日", &Cell.format_date(&1.service_date),
       key: :service_date, parse: &Cell.parse_date/1, required: true},
      {"曜", &Cell.format_weekday(&1.service_date)},
      {"提供形態", &Cell.format_enum(&1.provision_type, ProvisionType),
       key: :provision_type, parse: &Cell.parse_enum(&1, ProvisionType), required: true},
      {"開始", &Cell.format_time(&1.start_time), key: :start_time, parse: &Cell.parse_time/1},
      {"終了", &Cell.format_time(&1.end_time), key: :end_time, parse: &Cell.parse_time/1},
      {"送迎(往)", &Cell.format_bool(&1.pickup), key: :pickup, parse: &Cell.parse_bool/1},
      {"送迎(復)", &Cell.format_bool(&1.dropoff), key: :dropoff, parse: &Cell.parse_bool/1},
      {"備考", &Cell.format_text(&1.note), key: :note, parse: &Cell.parse_text/1},
      {"記録者", &User.display_name(&1.recorded_by)},
      {"記録日時(日本時間)", &Cell.format_datetime(&1.recorded_at)},
      {"記録ID", &Cell.format_id(&1.id)}
    ]
  end
end
