defmodule Ayumi.CSVTest do
  use ExUnit.Case, async: true

  alias Ayumi.CSV

  @bom "﻿"

  describe "encode/2" do
    test "starts with a UTF-8 BOM so Excel detects the encoding" do
      assert @bom <> _rest = CSV.encode(["氏名"], [["山田 太郎"]])
    end

    test "writes the header row first and uses CRLF line endings" do
      assert CSV.encode(["氏名", "備考"], [["山田", "良好"], ["佐藤", ""]]) ==
               @bom <> "氏名,備考\r\n山田,良好\r\n佐藤,\r\n"
    end

    test "quotes cells containing commas, quotes, and newlines" do
      csv = CSV.encode(["内容"], [["a,b"], ["say \"hi\""], ["line1\nline2"]])

      assert csv == @bom <> "内容\r\n\"a,b\"\r\n\"say \"\"hi\"\"\"\r\n\"line1\nline2\"\r\n"
    end

    test "prefixes formula-looking cells with an apostrophe" do
      csv = CSV.encode(["備考"], [["=1+1"], ["+81"], ["- 特になし"], ["@here"], ["\tx"]])

      assert csv ==
               @bom <> "備考\r\n'=1+1\r\n'+81\r\n'- 特になし\r\n'@here\r\n'\tx\r\n"
    end

    test "leaves ordinary cells untouched" do
      assert CSV.encode(["a"], [["09:00"], ["2026-09-17"], ["○"]]) ==
               @bom <> "a\r\n09:00\r\n2026-09-17\r\n○\r\n"
    end

    test "with no rows still emits the header" do
      assert CSV.encode(["氏名"], []) == @bom <> "氏名\r\n"
    end
  end

  describe "decode/1" do
    test "returns headers and rows keyed by header, numbered like Excel rows" do
      csv = @bom <> "氏名,備考\r\n山田,良好\r\n佐藤,\r\n"

      assert CSV.decode(csv) ==
               {:ok,
                %{
                  headers: ["氏名", "備考"],
                  rows: [
                    {2, %{"氏名" => "山田", "備考" => "良好"}},
                    {3, %{"氏名" => "佐藤", "備考" => ""}}
                  ]
                }}
    end

    test "accepts files without a BOM and with LF line endings" do
      assert {:ok, %{rows: [{2, %{"氏名" => "山田"}}]}} = CSV.decode("氏名\n山田\n")
    end

    test "round-trips what encode/2 writes, including escaped formula cells" do
      rows = [["a,b", "- 特になし"], ["line1\nline2", "=1+1"], ["say \"hi\"", "'quoted"]]

      assert {:ok, %{rows: decoded}} = CSV.decode(CSV.encode(["内容", "備考"], rows))

      assert Enum.map(decoded, fn {_no, cells} -> [cells["内容"], cells["備考"]] end) == [
               ["a,b", "- 特になし"],
               ["line1\nline2", "=1+1"],
               ["say \"hi\"", "'quoted"]
             ]
    end

    test "numbers rows by record, so a multi-line cell does not shift later rows" do
      csv = "備考\r\n\"1行目\n2行目\"\r\n次の行\r\n"

      assert {:ok, %{rows: [{2, _}, {3, %{"備考" => "次の行"}}]}} = CSV.decode(csv)
    end

    test "skips blank rows but keeps counting them" do
      csv = "氏名,備考\r\n山田,\r\n,\r\n\r\n佐藤,\r\n"

      assert {:ok, %{rows: [{2, _}, {5, %{"氏名" => "佐藤"}}]}} = CSV.decode(csv)
    end

    test "ignores the trailing empty columns Excel appends" do
      csv = "氏名,備考,,\r\n山田,良好,,\r\n"

      assert CSV.decode(csv) ==
               {:ok, %{headers: ["氏名", "備考"], rows: [{2, %{"氏名" => "山田", "備考" => "良好"}}]}}
    end

    test "treats a short row's missing cells as blank" do
      assert {:ok, %{rows: [{2, %{"氏名" => "山田", "備考" => ""}}]}} =
               CSV.decode("氏名,備考\r\n山田\r\n")
    end

    test "normalizes header width and spacing" do
      assert {:ok, %{headers: ["送迎(往)", "利用者ID"]}} =
               CSV.decode("送迎（往）, 利用者ＩＤ \r\n○,1\r\n")
    end

    test "rejects Shift_JIS files with advice on how to save from Excel" do
      # "氏名" in Shift_JIS.
      sjis = <<0x8E, 0x81, 0x96, 0xBC, ?\r, ?\n>>

      assert {:error, message} = CSV.decode(sjis)
      assert message =~ "CSV UTF-8"
    end

    test "rejects an empty file, a header-only file, and duplicate headers" do
      assert {:error, empty} = CSV.decode("")
      assert empty =~ "空"

      assert {:error, no_rows} = CSV.decode(@bom <> "氏名,備考\r\n")
      assert no_rows =~ "データ行"

      assert {:error, duplicate} = CSV.decode("氏名,氏名\r\n山田,山田\r\n")
      assert duplicate =~ "氏名"
    end

    test "rejects malformed quoting instead of raising" do
      assert {:error, message} = CSV.decode("備考\r\n\"閉じていない\r\n")
      assert message =~ "読み取れません"
    end
  end
end
