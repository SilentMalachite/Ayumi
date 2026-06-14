defmodule Ayumi.Plans.DisabilityCertificateTest do
  use ExUnit.Case, async: true

  alias Ayumi.Plans.DisabilityCertificate, as: Cert

  test "requires kind" do
    changeset = Cert.changeset(%Cert{}, %{number: "B-1"})
    refute changeset.valid?
    assert {"can't be blank", _} = changeset.errors[:kind]
  end

  test "kind only is valid; other fields are optional" do
    changeset = Cert.changeset(%Cert{}, %{kind: :physical})
    assert changeset.valid?
  end

  test "rejects an invalid kind" do
    changeset = Cert.changeset(%Cert{}, %{kind: :bogus})
    refute changeset.valid?
  end
end
