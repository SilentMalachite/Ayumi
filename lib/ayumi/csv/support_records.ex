defmodule Ayumi.CSV.SupportRecords do
  @moduledoc """
  CSV layout for support records (支援記録).
  Records must have `:service_user` and `:recorded_by` preloaded.
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

  defp columns do
    [
      {"利用者ID", &Cell.format_id(&1.service_user_id)},
      {"氏名", &Cell.format_text(&1.service_user.name)},
      {"在籍状態", &Cell.format_enum(&1.service_user.enrollment_status, EnrollmentStatus)},
      {"区分", &Cell.format_enum(&1.category, SupportRecordCategory)},
      {"内容", &Cell.format_text(&1.content)},
      {"記録者", &User.display_name(&1.recorded_by)},
      {"記録日時(日本時間)", &Cell.format_datetime(&1.recorded_at)},
      {"記録ID", &Cell.format_id(&1.id)}
    ]
  end
end
