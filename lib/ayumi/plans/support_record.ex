defmodule Ayumi.Plans.SupportRecord do
  @moduledoc """
  An append-only daily support record for a service user.

  `support_date` is the day the support happened; `recorded_at` is the moment the
  row was written. They differ for back-dated entries and CSV imports. When no
  support date is given it defaults to the Japanese calendar date of `recorded_at`,
  and it can never be later than that date.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ayumi.JST
  alias Ayumi.Plans.SupportRecordCategory

  @required_user_fields [:service_user_id, :content, :category]
  @user_fields [:support_date | @required_user_fields]
  @audit_fields [:recorded_by_id, :recorded_at]

  schema "support_records" do
    field :content, :string
    field :category, Ecto.Enum, values: SupportRecordCategory.all()
    field :support_date, :date
    field :recorded_at, :utc_datetime

    belongs_to :service_user, Ayumi.Plans.ServiceUser
    belongs_to :recorded_by, Ayumi.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(support_record, attrs) do
    support_record
    |> cast(attrs, @user_fields)
    |> validate_required(@required_user_fields)
    |> validate_inclusion(:category, SupportRecordCategory.all())
    |> foreign_key_constraint(:service_user_id)
    |> foreign_key_constraint(:recorded_by_id)
  end

  @doc """
  Stamps who recorded the row and when, then settles the support date against
  that clock: a missing date becomes the JST date of `recorded_at`, and a date
  after it is rejected. The clock is passed in, so this stays pure.
  """
  def put_audit(changeset, recorded_by_id, recorded_at) do
    changeset
    |> put_change(:recorded_by_id, recorded_by_id)
    |> put_change(:recorded_at, recorded_at)
    |> validate_required(@audit_fields)
    |> put_default_support_date(JST.today(recorded_at))
    |> validate_required([:support_date])
    |> validate_not_future(JST.today(recorded_at))
  end

  defp put_default_support_date(changeset, recorded_on) do
    if get_field(changeset, :support_date),
      do: changeset,
      else: put_change(changeset, :support_date, recorded_on)
  end

  defp validate_not_future(changeset, recorded_on) do
    validate_change(changeset, :support_date, fn :support_date, support_date ->
      if Date.compare(support_date, recorded_on) == :gt,
        do: [support_date: "未来の日付は指定できません"],
        else: []
    end)
  end
end
