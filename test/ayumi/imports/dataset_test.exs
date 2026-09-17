defmodule Ayumi.Imports.DatasetTest do
  use ExUnit.Case, async: true

  alias Ayumi.Imports.Dataset

  test "lists the importable datasets with Japanese labels" do
    assert Dataset.all() == [:attendance, :support_records, :service_users]
    assert Dataset.label(:attendance) == "出欠・実績記録"
    assert Dataset.label(:service_users) == "利用者台帳"
    assert Dataset.label(:support_records) == "支援記録"
    assert Dataset.label(:goal_progress) == nil
    assert {"利用者台帳", :service_users} in Dataset.options()
  end

  test "from_param/1 casts a form value without creating atoms" do
    assert Dataset.from_param("attendance") == {:ok, :attendance}
    assert Dataset.from_param("service_users") == {:ok, :service_users}
    assert Dataset.from_param("support_records") == {:ok, :support_records}
    assert Dataset.from_param("goal_progress") == :error
    assert Dataset.from_param(nil) == :error
  end
end
