defmodule Ayumi.Repo.Migrations.AddSupportDateToSupportRecords do
  use Ecto.Migration

  # `support_date` is the day the support happened, as opposed to `recorded_at`,
  # the moment the row was written. They differ for back-dated entries and for
  # rows imported from CSV.
  #
  # Existing rows are filled with the Japanese calendar date of `recorded_at`
  # (stored as UTC ISO 8601 text, e.g. "2026-09-17T09:24:46Z"; Japan is a fixed
  # +9h with no DST). This initializes a new derived column — no recorded fact is
  # overwritten. SQLite cannot add NOT NULL to an existing column, so presence is
  # enforced by the changeset.
  def up do
    alter table(:support_records) do
      add :support_date, :date
    end

    execute("UPDATE support_records SET support_date = date(recorded_at, '+9 hours')")

    create index(:support_records, [:support_date])
  end

  def down do
    drop index(:support_records, [:support_date])

    alter table(:support_records) do
      remove :support_date
    end
  end
end
