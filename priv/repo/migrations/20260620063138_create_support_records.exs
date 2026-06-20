defmodule Ayumi.Repo.Migrations.CreateSupportRecords do
  use Ecto.Migration

  def change do
    create table(:support_records) do
      add :service_user_id, references(:service_users, on_delete: :restrict), null: false
      add :content, :text, null: false
      add :category, :string, null: false
      add :recorded_by_id, references(:users, on_delete: :restrict), null: false
      add :recorded_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:support_records, [:service_user_id])
    create index(:support_records, [:recorded_at])
  end
end
