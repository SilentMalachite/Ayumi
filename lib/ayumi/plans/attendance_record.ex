defmodule Ayumi.Plans.AttendanceRecord do
  @moduledoc "An append-only daily attendance / service-provision record for a service user."
  use Ecto.Schema
  import Ecto.Changeset

  alias Ayumi.Plans.ProvisionType

  @user_fields [
    :service_user_id,
    :service_date,
    :provision_type,
    :pickup,
    :dropoff,
    :start_time,
    :end_time,
    :note
  ]
  @required [:service_user_id, :service_date, :provision_type]
  @audit_fields [:recorded_by_id, :recorded_at]

  schema "attendance_records" do
    field :service_date, :date
    field :provision_type, Ecto.Enum, values: ProvisionType.all()
    field :pickup, :boolean, default: false
    field :dropoff, :boolean, default: false
    field :start_time, :time
    field :end_time, :time
    field :note, :string
    field :recorded_at, :utc_datetime

    belongs_to :service_user, Ayumi.Plans.ServiceUser
    belongs_to :recorded_by, Ayumi.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(attendance_record, attrs) do
    attendance_record
    |> cast(attrs, @user_fields)
    |> validate_required(@required)
    |> validate_inclusion(:provision_type, ProvisionType.all())
    |> validate_time_order()
    |> foreign_key_constraint(:service_user_id)
    |> foreign_key_constraint(:recorded_by_id)
  end

  def put_audit(changeset, recorded_by_id, recorded_at) do
    changeset
    |> put_change(:recorded_by_id, recorded_by_id)
    |> put_change(:recorded_at, recorded_at)
    |> validate_required(@audit_fields)
  end

  defp validate_time_order(changeset) do
    start_t = get_field(changeset, :start_time)
    end_t = get_field(changeset, :end_time)

    if start_t && end_t && Time.compare(end_t, start_t) != :gt do
      add_error(changeset, :end_time, "終了時刻は開始時刻より後にしてください")
    else
      changeset
    end
  end
end
