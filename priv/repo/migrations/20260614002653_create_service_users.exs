defmodule Ayumi.Repo.Migrations.CreateServiceUsers do
  use Ecto.Migration

  def change do
    create table(:service_users) do
      add :name, :string, null: false
      add :name_kana, :string

      timestamps(type: :utc_datetime)
    end
  end
end
