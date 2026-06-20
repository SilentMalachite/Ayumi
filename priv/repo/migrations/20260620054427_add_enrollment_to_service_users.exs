defmodule Ayumi.Repo.Migrations.AddEnrollmentToServiceUsers do
  use Ecto.Migration

  def change do
    alter table(:service_users) do
      add :enrollment_status, :string, default: "enrolled", null: false
      add :enrollment_start_date, :date
    end
  end
end
