defmodule Ayumi.Repo.Migrations.CreateGoalProgresses do
  use Ecto.Migration

  def change do
    create table(:goal_progresses) do
      add :goal_id, references(:goals, on_delete: :restrict), null: false
      add :stage, :string, null: false
      add :note, :text
      add :recorded_by_id, references(:users, on_delete: :restrict), null: false
      add :recorded_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:goal_progresses, [:goal_id])
    create index(:goal_progresses, [:recorded_by_id])
    create index(:goal_progresses, [:goal_id, :id])
  end
end
