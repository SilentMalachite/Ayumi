defmodule Ayumi.Repo.Migrations.AddBasicInfoToServiceUsers do
  use Ecto.Migration

  def change do
    alter table(:service_users) do
      add :birthdate, :date
      add :gender, :string
      add :postal_code, :string
      add :address, :string
      add :phone, :string
      add :emergency_contact_name, :string
      add :emergency_contact_relation, :string
      add :emergency_contact_phone, :string
      add :recipient_cert_number, :string
      add :recipient_cert_municipality, :string
      add :disability_support_category, :string
      add :benefit_amount, :string
      add :recipient_cert_expiry, :date
      add :clinic_name, :string
      add :attending_physician, :string
      add :medication_notes, :text
      add :consultation_office, :string
      add :consultation_staff, :string
      add :notes, :text
    end
  end
end
