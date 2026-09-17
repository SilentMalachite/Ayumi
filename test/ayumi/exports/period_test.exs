defmodule Ayumi.Exports.PeriodTest do
  use ExUnit.Case, async: true

  alias Ayumi.Exports.Period

  describe "units/0 and labels" do
    test "lists the units in display order with Japanese labels" do
      assert Period.units() == [:week, :month, :fiscal_year, :calendar_year]
      assert Period.unit_label(:week) == "週"
      assert Period.unit_label(:month) == "月"
      assert Period.unit_label(:fiscal_year) == "年度"
      assert Period.unit_label(:calendar_year) == "暦年"
      assert Period.unit_label(:unknown) == nil
      assert {"年度", :fiscal_year} in Period.unit_options()
    end
  end

  describe "range/2 :week" do
    test "starts on Monday and ends on Sunday" do
      # 2026-09-17 is a Thursday.
      assert Period.range(:week, ~D[2026-09-17]) == {~D[2026-09-14], ~D[2026-09-20]}
    end

    test "a Sunday belongs to the week that started the previous Monday" do
      assert Period.range(:week, ~D[2026-09-20]) == {~D[2026-09-14], ~D[2026-09-20]}
    end

    test "a Monday starts its own week" do
      assert Period.range(:week, ~D[2026-09-14]) == {~D[2026-09-14], ~D[2026-09-20]}
    end

    test "spans a year boundary" do
      assert Period.range(:week, ~D[2027-01-01]) == {~D[2026-12-28], ~D[2027-01-03]}
    end
  end

  describe "range/2 :month" do
    test "covers the whole month" do
      assert Period.range(:month, ~D[2026-09-17]) == {~D[2026-09-01], ~D[2026-09-30]}
    end

    test "handles leap-year February" do
      assert Period.range(:month, ~D[2028-02-10]) == {~D[2028-02-01], ~D[2028-02-29]}
    end
  end

  describe "range/2 :fiscal_year" do
    test "April through December belongs to the same fiscal year" do
      assert Period.range(:fiscal_year, ~D[2026-04-01]) == {~D[2026-04-01], ~D[2027-03-31]}
      assert Period.range(:fiscal_year, ~D[2026-12-31]) == {~D[2026-04-01], ~D[2027-03-31]}
    end

    test "January through March belongs to the previous fiscal year" do
      assert Period.range(:fiscal_year, ~D[2027-01-01]) == {~D[2026-04-01], ~D[2027-03-31]}
      assert Period.range(:fiscal_year, ~D[2027-03-31]) == {~D[2026-04-01], ~D[2027-03-31]}
    end
  end

  describe "range/2 :calendar_year" do
    test "covers January 1 through December 31" do
      assert Period.range(:calendar_year, ~D[2026-09-17]) == {~D[2026-01-01], ~D[2026-12-31]}
    end
  end

  describe "label/2" do
    test "names the period and shows its date range" do
      assert Period.label(:week, ~D[2026-09-17]) == "2026-09-14 〜 2026-09-20"
      assert Period.label(:month, ~D[2026-09-17]) == "2026年9月（2026-09-01 〜 2026-09-30）"

      assert Period.label(:fiscal_year, ~D[2027-02-01]) ==
               "2026年度（2026-04-01 〜 2027-03-31）"

      assert Period.label(:calendar_year, ~D[2026-09-17]) ==
               "2026年（2026-01-01 〜 2026-12-31）"
    end
  end

  describe "filename_part/2" do
    test "is short and sorts naturally" do
      assert Period.filename_part(:week, ~D[2026-09-17]) == "2026-09-14週"
      assert Period.filename_part(:month, ~D[2026-09-17]) == "2026年09月"
      assert Period.filename_part(:fiscal_year, ~D[2027-02-01]) == "2026年度"
      assert Period.filename_part(:calendar_year, ~D[2026-09-17]) == "2026年"
    end
  end
end
