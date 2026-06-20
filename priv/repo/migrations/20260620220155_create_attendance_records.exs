defmodule Ayumi.Repo.Migrations.CreateAttendanceRecords do
  use Ecto.Migration

  def change do
    create table(:attendance_records) do
      add :service_user_id, references(:service_users, on_delete: :restrict), null: false
      add :service_date, :date, null: false
      add :provision_type, :string, null: false
      add :pickup, :boolean, null: false, default: false
      add :dropoff, :boolean, null: false, default: false
      add :start_time, :time
      add :end_time, :time
      add :note, :text
      add :recorded_by_id, references(:users, on_delete: :restrict), null: false
      add :recorded_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:attendance_records, [:service_user_id, :service_date])
  end
end
