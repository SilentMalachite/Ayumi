defmodule Ayumi.Imports.DatasetTest do
  use ExUnit.Case, async: true

  alias Ayumi.Imports.Dataset

  test "lists the importable datasets with Japanese labels" do
    assert Dataset.all() == [:attendance, :service_users]
    assert Dataset.label(:attendance) == "出欠・実績記録"
    assert Dataset.label(:service_users) == "利用者台帳"
    assert Dataset.label(:support_records) == nil
    assert {"利用者台帳", :service_users} in Dataset.options()
  end

  test "from_param/1 casts a form value without creating atoms" do
    assert Dataset.from_param("attendance") == {:ok, :attendance}
    assert Dataset.from_param("service_users") == {:ok, :service_users}
    assert Dataset.from_param("support_records") == :error
    assert Dataset.from_param(nil) == :error
  end
end
