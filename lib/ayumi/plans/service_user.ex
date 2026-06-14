defmodule Ayumi.Plans.ServiceUser do
  @moduledoc "A service user (利用者) with editable basic info, tracked across support plans."
  use Ecto.Schema
  import Ecto.Changeset

  alias Ayumi.Plans.{Gender, SupportCategory}

  @flat_fields [
    :name,
    :name_kana,
    :birthdate,
    :gender,
    :postal_code,
    :address,
    :phone,
    :emergency_contact_name,
    :emergency_contact_relation,
    :emergency_contact_phone,
    :recipient_cert_number,
    :recipient_cert_municipality,
    :disability_support_category,
    :benefit_amount,
    :recipient_cert_expiry,
    :clinic_name,
    :attending_physician,
    :medication_notes,
    :consultation_office,
    :consultation_staff,
    :notes
  ]

  schema "service_users" do
    field :name, :string
    field :name_kana, :string
    field :birthdate, :date
    field :gender, Ecto.Enum, values: Gender.all()
    field :postal_code, :string
    field :address, :string
    field :phone, :string
    field :emergency_contact_name, :string
    field :emergency_contact_relation, :string
    field :emergency_contact_phone, :string
    field :recipient_cert_number, :string
    field :recipient_cert_municipality, :string
    field :disability_support_category, Ecto.Enum, values: SupportCategory.all()
    field :benefit_amount, :string
    field :recipient_cert_expiry, :date
    field :clinic_name, :string
    field :attending_physician, :string
    field :medication_notes, :string
    field :consultation_office, :string
    field :consultation_staff, :string
    field :notes, :string

    has_many :support_plans, Ayumi.Plans.SupportPlan

    has_many :disability_certificates, Ayumi.Plans.DisabilityCertificate, on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(service_user, attrs) do
    service_user
    |> cast(attrs, @flat_fields)
    |> validate_required([:name])
    |> cast_assoc(:disability_certificates,
      with: &Ayumi.Plans.DisabilityCertificate.changeset/2
    )
  end

  @doc """
  Age in whole years on `today`, derived from `birthdate`. Display-only; never
  stored. Returns nil when no birthdate is set.
  """
  def age(%__MODULE__{birthdate: nil}, %Date{}), do: nil

  def age(%__MODULE__{birthdate: %Date{} = birthdate}, %Date{} = today) do
    years = today.year - birthdate.year

    if {today.month, today.day} < {birthdate.month, birthdate.day} do
      years - 1
    else
      years
    end
  end
end
