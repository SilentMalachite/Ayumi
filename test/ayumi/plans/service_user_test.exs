defmodule Ayumi.Plans.ServiceUserTest do
  use Ayumi.DataCase, async: true

  alias Ayumi.Plans.ServiceUser

  test "requires name" do
    changeset = ServiceUser.changeset(%ServiceUser{}, %{})
    refute changeset.valid?
    assert %{name: ["can't be blank"]} = errors_on(changeset)
  end

  test "name_kana is optional" do
    changeset = ServiceUser.changeset(%ServiceUser{}, %{name: "山田 太郎"})
    assert changeset.valid?
  end
end
