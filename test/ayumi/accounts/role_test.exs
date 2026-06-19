defmodule Ayumi.Accounts.RoleTest do
  use ExUnit.Case, async: true

  alias Ayumi.Accounts.Role

  test "all/0 returns both roles in order" do
    assert Role.all() == [:manager, :supporter]
  end

  test "label/1 returns Japanese labels" do
    assert Role.label(:manager) == "サービス管理責任者"
    assert Role.label(:supporter) == "支援者"
  end

  test "label/1 returns nil for unknown value" do
    assert Role.label(:unknown) == nil
  end

  test "options/0 returns {label, value} pairs for select inputs" do
    assert Role.options() == [
             {"サービス管理責任者", :manager},
             {"支援者", :supporter}
           ]
  end
end
