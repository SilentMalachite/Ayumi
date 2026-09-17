defmodule Ayumi.JSTTest do
  use ExUnit.Case, async: true

  alias Ayumi.JST

  describe "today/1" do
    test "rolls over to the next day at 15:00 UTC" do
      assert JST.today(~U[2026-08-31 14:59:59Z]) == ~D[2026-08-31]
      assert JST.today(~U[2026-08-31 15:00:00Z]) == ~D[2026-09-01]
    end
  end

  describe "format/1" do
    test "renders a UTC datetime as JST wall-clock text with seconds" do
      assert JST.format(~U[2026-09-17 01:02:03Z]) == "2026-09-17 10:02:03"
      assert JST.format(~U[2026-12-31 15:00:00Z]) == "2027-01-01 00:00:00"
    end
  end

  describe "utc_range/2" do
    test "returns the half-open UTC range covering the JST dates" do
      assert JST.utc_range(~D[2026-09-01], ~D[2026-09-30]) ==
               {~U[2026-08-31 15:00:00Z], ~U[2026-09-30 15:00:00Z]}
    end

    test "a single day spans 24 hours" do
      {from, to} = JST.utc_range(~D[2026-09-17], ~D[2026-09-17])
      assert DateTime.diff(to, from, :hour) == 24
    end
  end
end
