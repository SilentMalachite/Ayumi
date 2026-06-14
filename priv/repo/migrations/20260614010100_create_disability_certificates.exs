defmodule Ayumi.Repo.Migrations.CreateDisabilityCertificates do
  use Ecto.Migration

  def change do
    create table(:disability_certificates) do
      add :service_user_id, references(:service_users, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :number, :string
      add :disability_name, :string
      add :grade, :string

      timestamps(type: :utc_datetime)
    end

    create index(:disability_certificates, [:service_user_id])
  end
end
