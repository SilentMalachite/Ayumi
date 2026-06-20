defmodule Ayumi.Plans.SupportRecord do
  @moduledoc "An append-only daily support record for a service user."
  use Ecto.Schema
  import Ecto.Changeset

  alias Ayumi.Plans.SupportRecordCategory

  @user_fields [:service_user_id, :content, :category]
  @audit_fields [:recorded_by_id, :recorded_at]

  schema "support_records" do
    field :content, :string
    field :category, Ecto.Enum, values: SupportRecordCategory.all()
    field :recorded_at, :utc_datetime

    belongs_to :service_user, Ayumi.Plans.ServiceUser
    belongs_to :recorded_by, Ayumi.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(support_record, attrs) do
    support_record
    |> cast(attrs, @user_fields)
    |> validate_required(@user_fields)
    |> validate_inclusion(:category, SupportRecordCategory.all())
    |> foreign_key_constraint(:service_user_id)
    |> foreign_key_constraint(:recorded_by_id)
  end

  def put_audit(changeset, recorded_by_id, recorded_at) do
    changeset
    |> put_change(:recorded_by_id, recorded_by_id)
    |> put_change(:recorded_at, recorded_at)
    |> validate_required(@audit_fields)
  end
end
