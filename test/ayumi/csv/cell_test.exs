defmodule Ayumi.CSV.CellTest do
  use ExUnit.Case, async: true

  alias Ayumi.CSV.Cell
  alias Ayumi.Plans.ProvisionType

  test "format_text/1 turns nil into an empty cell" do
    assert Cell.format_text(nil) == ""
    assert Cell.format_text("所見") == "所見"
  end

  test "format_id/1 renders integers and nil" do
    assert Cell.format_id(42) == "42"
    assert Cell.format_id(nil) == ""
  end

  test "format_date/1 is ISO 8601" do
    assert Cell.format_date(~D[2026-09-01]) == "2026-09-01"
    assert Cell.format_date(nil) == ""
  end

  test "format_weekday/1 is the Japanese one-letter weekday" do
    assert Cell.format_weekday(~D[2026-09-14]) == "月"
    assert Cell.format_weekday(~D[2026-09-20]) == "日"
    assert Cell.format_weekday(nil) == ""
  end

  test "format_time/1 is HH:MM without seconds" do
    assert Cell.format_time(~T[09:00:00]) == "09:00"
    assert Cell.format_time(~T[15:30:45]) == "15:30"
    assert Cell.format_time(nil) == ""
  end

  test "format_bool/1 is a circle or blank, matching the printed sheet" do
    assert Cell.format_bool(true) == "○"
    assert Cell.format_bool(false) == ""
    assert Cell.format_bool(nil) == ""
  end

  test "format_datetime/1 is JST with seconds" do
    assert Cell.format_datetime(~U[2026-09-17 01:02:03Z]) == "2026-09-17 10:02:03"
    assert Cell.format_datetime(nil) == ""
  end

  test "format_enum/2 uses the enum module's Japanese label" do
    assert Cell.format_enum(:commute, ProvisionType) == "通所"
    assert Cell.format_enum(nil, ProvisionType) == ""
  end
end
