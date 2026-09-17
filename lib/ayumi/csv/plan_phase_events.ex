defmodule Ayumi.CSV.PlanPhaseEvents do
  @moduledoc """
  CSV layout for the plan phase history (計画段階の履歴). Rows must have
  `:recorded_by` and `support_plan: :service_user` preloaded.
  """

  alias Ayumi.Accounts.User
  alias Ayumi.CSV.Cell
  alias Ayumi.CSV.Columns
  alias Ayumi.Plans.EnrollmentStatus
  alias Ayumi.Plans.PlanPhaseStage

  @doc "The header row."
  def headers, do: Columns.headers(columns())

  @doc "Renders rows of cells aligned with `headers/0`."
  def dump(rows), do: Columns.dump(columns(), rows)

  defp columns do
    [
      {"利用者ID", &Cell.format_id(service_user(&1).id)},
      {"氏名", &Cell.format_text(service_user(&1).name)},
      {"在籍状態", &Cell.format_enum(service_user(&1).enrollment_status, EnrollmentStatus)},
      {"計画ID", &Cell.format_id(&1.support_plan_id)},
      {"計画期間開始", &Cell.format_date(&1.support_plan.period_start)},
      {"計画期間終了", &Cell.format_date(&1.support_plan.period_end)},
      {"段階", &Cell.format_enum(&1.stage, PlanPhaseStage)},
      {"所見", &Cell.format_text(&1.note)},
      {"記録者", &User.display_name(&1.recorded_by)},
      {"記録日時(日本時間)", &Cell.format_datetime(&1.recorded_at)},
      {"記録ID", &Cell.format_id(&1.id)}
    ]
  end

  defp service_user(row), do: row.support_plan.service_user
end
