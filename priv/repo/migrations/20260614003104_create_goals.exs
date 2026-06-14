defmodule Ayumi.Repo.Migrations.CreateGoals do
  use Ecto.Migration

  def change do
    create table(:goals) do
      add :support_plan_id, references(:support_plans, on_delete: :restrict), null: false
      add :description, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:goals, [:support_plan_id])
  end
end
