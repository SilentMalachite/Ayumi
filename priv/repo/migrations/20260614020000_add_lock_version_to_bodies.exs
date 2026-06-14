defmodule Ayumi.Repo.Migrations.AddLockVersionToBodies do
  use Ecto.Migration

  def change do
    alter table(:service_users) do
      add :lock_version, :integer, null: false, default: 0
    end

    alter table(:support_plans) do
      add :lock_version, :integer, null: false, default: 0
    end

    alter table(:goals) do
      add :lock_version, :integer, null: false, default: 0
    end
  end
end
