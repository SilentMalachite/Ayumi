defmodule Ayumi.CSV.Attendance do
  @moduledoc """
  CSV layout for attendance records (出欠・実績記録). Each column is defined once,
  as a header plus the function that renders its cell, so the header order and
  the cell order cannot drift apart. Headers reuse the printed sheet's wording.

  Records must have `:service_user` and `:recorded_by` preloaded.
  """

  alias Ayumi.Accounts.User
  alias Ayumi.CSV.Cell
  alias Ayumi.Plans.ProvisionType

  @doc "The header row."
  def headers, do: Enum.map(columns(), fn {header, _dump} -> header end)

  @doc "Renders records as rows of cells aligned with `headers/0`."
  def dump(records) when is_list(records) do
    Enum.map(records, fn record ->
      Enum.map(columns(), fn {_header, dump} -> dump.(record) end)
    end)
  end

  # A function rather than a module attribute: anonymous functions cannot be
  # stored in attributes.
  defp columns do
    [
      {"利用者ID", &Cell.format_id(&1.service_user_id)},
      {"氏名", &Cell.format_text(&1.service_user.name)},
      {"利用日", &Cell.format_date(&1.service_date)},
      {"曜", &Cell.format_weekday(&1.service_date)},
      {"提供形態", &Cell.format_enum(&1.provision_type, ProvisionType)},
      {"開始", &Cell.format_time(&1.start_time)},
      {"終了", &Cell.format_time(&1.end_time)},
      {"送迎(往)", &Cell.format_bool(&1.pickup)},
      {"送迎(復)", &Cell.format_bool(&1.dropoff)},
      {"備考", &Cell.format_text(&1.note)},
      {"記録者", &User.display_name(&1.recorded_by)},
      {"記録日時(日本時間)", &Cell.format_datetime(&1.recorded_at)},
      {"記録ID", &Cell.format_id(&1.id)}
    ]
  end
end
