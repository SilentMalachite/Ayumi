defmodule Ayumi.PlansTest do
  use Ayumi.DataCase, async: true

  alias Ayumi.Plans
  alias Ayumi.Plans.ServiceUser

  import Ayumi.PlansFixtures

  describe "service users" do
    test "create_service_user/1 with valid data" do
      assert {:ok, %ServiceUser{} = su} = Plans.create_service_user(%{name: "佐藤 花子"})
      assert su.name == "佐藤 花子"
    end

    test "create_service_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Plans.create_service_user(%{})
    end

    test "list_service_users/0 orders by kana then name" do
      service_user_fixture(%{name: "B", name_kana: "い"})
      service_user_fixture(%{name: "A", name_kana: "あ"})
      assert ["あ", "い"] = Plans.list_service_users() |> Enum.map(& &1.name_kana)
    end

    test "get_service_user!/1 returns the record" do
      su = service_user_fixture()
      assert Plans.get_service_user!(su.id).id == su.id
    end
  end
end
