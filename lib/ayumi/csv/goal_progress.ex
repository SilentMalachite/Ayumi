defmodule Ayumi.CSV.GoalProgress do
  @moduledoc """
  CSV layout for the goal progress history (目標進捗の履歴). Rows must have
  `:recorded_by` and `goal: [support_plan: :service_user]` preloaded.
  """

  alias Ayumi.Accounts.User
  alias Ayumi.CSV.Cell
  alias Ayumi.CSV.Columns
  alias Ayumi.Plans.EnrollmentStatus
  alias Ayumi.Plans.GoalProgressStage

  @doc "The header row."
  def headers, do: Columns.headers(columns())

  @doc "Renders rows of cells aligned with `headers/0`."
  def dump(rows), do: Columns.dump(columns(), rows)

  defp columns do
    [
      {"利用者ID", &Cell.format_id(service_user(&1).id)},
      {"氏名", &Cell.format_text(service_user(&1).name)},
      {"在籍状態", &Cell.format_enum(service_user(&1).enrollment_status, EnrollmentStatus)},
      {"計画ID", &Cell.format_id(&1.goal.support_plan.id)},
      {"計画期間開始", &Cell.format_date(&1.goal.support_plan.period_start)},
      {"計画期間終了", &Cell.format_date(&1.goal.support_plan.period_end)},
      {"目標ID", &Cell.format_id(&1.goal_id)},
      {"短期目標", &Cell.format_text(&1.goal.description)},
      {"進捗", &Cell.format_enum(&1.stage, GoalProgressStage)},
      {"所見", &Cell.format_text(&1.note)},
      {"記録者", &User.display_name(&1.recorded_by)},
      {"記録日時(日本時間)", &Cell.format_datetime(&1.recorded_at)},
      {"記録ID", &Cell.format_id(&1.id)}
    ]
  end

  defp service_user(row), do: row.goal.support_plan.service_user
end
