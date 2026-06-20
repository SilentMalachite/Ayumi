defmodule Ayumi.Plans.SupportRecord do
  @moduledoc "An append-only daily support record for a service user."
  use Ecto.Schema
  import Ecto.Changeset

  alias Ayumi.Plans.SupportRecordCategory

  @required [:service_user_id, :content, :category, :recorded_by_id, :recorded_at]
  @optional []

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
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:category, SupportRecordCategory.all())
    |> foreign_key_constraint(:service_user_id)
    |> foreign_key_constraint(:recorded_by_id)
  end
end
