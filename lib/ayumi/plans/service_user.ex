defmodule Ayumi.Plans.ServiceUser do
  @moduledoc "A service user (利用者) tracked across one or more support plans."
  use Ecto.Schema
  import Ecto.Changeset

  schema "service_users" do
    field :name, :string
    field :name_kana, :string

    has_many :support_plans, Ayumi.Plans.SupportPlan

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(service_user, attrs) do
    service_user
    |> cast(attrs, [:name, :name_kana])
    |> validate_required([:name])
  end
end
