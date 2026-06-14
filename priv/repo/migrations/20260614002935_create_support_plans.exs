defmodule Ayumi.Repo.Migrations.CreateSupportPlans do
  use Ecto.Migration

  def change do
    create table(:support_plans) do
      add :service_user_id, references(:service_users, on_delete: :restrict), null: false
      add :staff_id, references(:users, on_delete: :restrict), null: false
      add :period_start, :date, null: false
      add :period_end, :date, null: false
      add :long_term_goal, :text, null: false
      add :next_monitoring_date, :date, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:support_plans, [:service_user_id])
    create index(:support_plans, [:staff_id])
  end
end
