defmodule Ayumi.PlansFixtures do
  @moduledoc "Test fixtures for the Plans context."

  import Ayumi.AccountsFixtures

  alias Ayumi.Plans

  def service_user_fixture(attrs \\ %{}) do
    {:ok, service_user} =
      attrs
      |> Enum.into(%{name: "山田 太郎", name_kana: "やまだ たろう"})
      |> Plans.create_service_user()

    service_user
  end
end
