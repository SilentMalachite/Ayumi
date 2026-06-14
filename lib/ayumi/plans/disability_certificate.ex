defmodule Ayumi.Plans.DisabilityCertificate do
  @moduledoc "A disability certificate (障害者手帳) belonging to a service user."
  use Ecto.Schema
  import Ecto.Changeset

  alias Ayumi.Plans.CertificateKind

  schema "disability_certificates" do
    field :kind, Ecto.Enum, values: CertificateKind.all()
    field :number, :string
    field :disability_name, :string
    field :grade, :string

    belongs_to :service_user, Ayumi.Plans.ServiceUser

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(certificate, attrs) do
    certificate
    |> cast(attrs, [:kind, :number, :disability_name, :grade])
    |> validate_required([:kind])
    |> foreign_key_constraint(:service_user_id)
  end
end
