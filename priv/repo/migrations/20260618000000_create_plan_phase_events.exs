defmodule Ayumi.Repo.Migrations.CreatePlanPhaseEvents do
  use Ecto.Migration

  def change do
    create table(:plan_phase_events) do
      add :support_plan_id, references(:support_plans, on_delete: :restrict), null: false
      add :stage, :string, null: false
      add :note, :text
      add :recorded_by_id, references(:users, on_delete: :restrict), null: false
      add :recorded_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:plan_phase_events, [:support_plan_id])
    create index(:plan_phase_events, [:recorded_by_id])
    create index(:plan_phase_events, [:support_plan_id, :id])
  end
end
