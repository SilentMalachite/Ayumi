defmodule Ayumi.Exports.Request do
  @moduledoc """
  What to export: a dataset, the period containing an anchor date, and an
  optional service user. Not persisted — an embedded schema so that the export
  form and the download URL are validated by one changeset.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ayumi.Exports.Dataset
  alias Ayumi.Exports.Period

  @primary_key false
  embedded_schema do
    field :dataset, Ecto.Enum, values: Dataset.all()
    field :unit, Ecto.Enum, values: Period.units()
    field :anchor_date, :date
    field :service_user_id, :integer
  end

  @doc false
  def changeset(%__MODULE__{} = request, attrs) do
    request
    |> cast(attrs, [:dataset, :unit, :anchor_date, :service_user_id])
    |> validate_required([:dataset, :unit], message: "を選択してください")
    |> validate_required([:anchor_date], message: "を指定してください")
  end
end
