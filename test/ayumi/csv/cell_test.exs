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

  describe "parse_text/1" do
    test "keeps free text as written, only normalizing line endings" do
      assert Cell.parse_text("ＡＢＣ 所見") == {:ok, "ＡＢＣ 所見"}
      assert Cell.parse_text("1行目\r\n2行目") == {:ok, "1行目\n2行目"}
    end

    test "a blank cell is nil" do
      assert Cell.parse_text("") == {:ok, nil}
      assert Cell.parse_text("  　 ") == {:ok, nil}
    end
  end

  describe "parse_id/1" do
    test "reads digits, including full-width ones Excel users may type" do
      assert Cell.parse_id("42") == {:ok, 42}
      assert Cell.parse_id(" ４２ ") == {:ok, 42}
      assert Cell.parse_id("") == {:ok, nil}
    end

    test "rejects anything else with a Japanese message" do
      assert {:error, message} = Cell.parse_id("4a")
      assert message =~ "数字"
      assert {:error, _} = Cell.parse_id("-1")
      assert {:error, _} = Cell.parse_id("1.5")
    end
  end

  describe "parse_date/1" do
    test "reads ISO dates and the slash form Excel writes" do
      assert Cell.parse_date("2026-09-01") == {:ok, ~D[2026-09-01]}
      assert Cell.parse_date("2026/9/1") == {:ok, ~D[2026-09-01]}
      assert Cell.parse_date("２０２６／０９／０１") == {:ok, ~D[2026-09-01]}
      assert Cell.parse_date("") == {:ok, nil}
    end

    test "rejects impossible dates and year-less text" do
      assert {:error, message} = Cell.parse_date("2026-02-30")
      assert message =~ "日付"
      assert {:error, _} = Cell.parse_date("9月1日")
      assert {:error, _} = Cell.parse_date("46266")
    end
  end

  describe "parse_time/1" do
    test "reads H:MM, HH:MM, and HH:MM:SS" do
      assert Cell.parse_time("9:00") == {:ok, ~T[09:00:00]}
      assert Cell.parse_time("09:00") == {:ok, ~T[09:00:00]}
      assert Cell.parse_time("15:30:45") == {:ok, ~T[15:30:45]}
      assert Cell.parse_time("９：００") == {:ok, ~T[09:00:00]}
      assert Cell.parse_time("") == {:ok, nil}
    end

    test "rejects impossible times" do
      assert {:error, message} = Cell.parse_time("25:00")
      assert message =~ "時刻"
      assert {:error, _} = Cell.parse_time("9時")
      assert {:error, _} = Cell.parse_time("0.375")
    end
  end

  describe "parse_bool/1" do
    test "reads the circle the export writes, and common alternatives" do
      for cell <- ["○", "〇", "◯", "1", "TRUE", "true", " ○ "] do
        assert Cell.parse_bool(cell) == {:ok, true}
      end

      for cell <- ["", "×", "0", "FALSE", "false"] do
        assert Cell.parse_bool(cell) == {:ok, false}
      end
    end

    test "rejects anything else" do
      assert {:error, message} = Cell.parse_bool("あり")
      assert message =~ "○"
    end
  end

  describe "parse_enum/2" do
    test "reads the Japanese label the export writes" do
      assert Cell.parse_enum("通所", ProvisionType) == {:ok, :commute}
      assert Cell.parse_enum(" 欠席時対応 ", ProvisionType) == {:ok, :absence_support}
      assert Cell.parse_enum("", ProvisionType) == {:ok, nil}
    end

    test "lists the accepted labels when the cell is unknown" do
      assert {:error, message} = Cell.parse_enum("出席", ProvisionType)
      assert message =~ "通所"
      assert message =~ "欠席時対応"
    end
  end

  test "every formatted cell parses back to its value" do
    assert Cell.parse_date(Cell.format_date(~D[2026-09-01])) == {:ok, ~D[2026-09-01]}
    assert Cell.parse_time(Cell.format_time(~T[09:05:00])) == {:ok, ~T[09:05:00]}
    assert Cell.parse_bool(Cell.format_bool(true)) == {:ok, true}
    assert Cell.parse_bool(Cell.format_bool(false)) == {:ok, false}
    assert Cell.parse_id(Cell.format_id(7)) == {:ok, 7}

    assert Cell.parse_enum(Cell.format_enum(:absence, ProvisionType), ProvisionType) ==
             {:ok, :absence}
  end
end
