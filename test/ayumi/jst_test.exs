defmodule Ayumi.JSTTest do
  use ExUnit.Case, async: true

  alias Ayumi.JST

  describe "today/1" do
    test "rolls over to the next day at 15:00 UTC" do
      assert JST.today(~U[2026-08-31 14:59:59Z]) == ~D[2026-08-31]
      assert JST.today(~U[2026-08-31 15:00:00Z]) == ~D[2026-09-01]
    end
  end

  describe "the application's idea of today" do
    # Between 00:00 and 09:00 in Japan, UTC is still on the previous day. Asking
    # for today in UTC then opens last month's attendance on the 1st and judges
    # deadlines a day late, and no ordinary test catches it because it depends on
    # the time of day. So the rule is checked on the source instead.
    test "is always taken on the Japanese calendar (JST.today/1), never Date.utc_today/0" do
      paths = Path.wildcard(Path.expand("../../lib/**/*.ex", __DIR__))
      assert length(paths) > 10, "expected to scan the lib/ sources, found #{length(paths)}"

      offenders =
        for path <- paths,
            {line, number} <- path |> File.read!() |> String.split("\n") |> Enum.with_index(1),
            String.contains?(line, "Date.utc_today("),
            do: "#{Path.relative_to_cwd(path)}:#{number}"

      assert offenders == [],
             "use Ayumi.JST.today() instead of Date.utc_today() at:\n" <>
               Enum.join(offenders, "\n")
    end
  end

  describe "format/1" do
    test "renders a UTC datetime as JST wall-clock text with seconds" do
      assert JST.format(~U[2026-09-17 01:02:03Z]) == "2026-09-17 10:02:03"
      assert JST.format(~U[2026-12-31 15:00:00Z]) == "2027-01-01 00:00:00"
    end

    test "can stop at minutes, for screens" do
      assert JST.format(~U[2026-09-17 01:02:03Z], :minute) == "2026-09-17 10:02"
      assert JST.format(~U[2026-09-17 01:02:03Z], :second) == "2026-09-17 10:02:03"
    end

    test "accepts microsecond precision" do
      assert JST.format(~U[2026-09-17 01:02:03.456789Z]) == "2026-09-17 10:02:03"
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
