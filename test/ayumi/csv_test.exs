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
end
