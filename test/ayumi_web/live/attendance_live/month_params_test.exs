defmodule AyumiWeb.AttendanceLive.MonthParamsTest do
  use ExUnit.Case, async: true

  alias AyumiWeb.AttendanceLive.MonthParams

  # The first of the month in Japan while it is still the last day of the previous
  # month in UTC — the case the Japanese calendar default exists for.
  @today ~D[2026-09-01]

  test "reads year and month from the params" do
    assert MonthParams.parse(%{"year" => "2025", "month" => "3"}, @today) == {2025, 3}
  end

  test "falls back to the given today when params are missing" do
    assert MonthParams.parse(%{}, @today) == {2026, 9}
    assert MonthParams.parse(%{"year" => "2025"}, @today) == {2025, 9}
  end

  test "falls back to the given today's month when the month is invalid" do
    assert MonthParams.parse(%{"year" => "bad", "month" => "13"}, @today) == {2026, 9}
    assert MonthParams.parse(%{"month" => "x"}, @today) == {2026, 9}
  end

  test "defaults today to the Japanese calendar date" do
    today = Ayumi.JST.today()
    assert MonthParams.parse(%{}) == {today.year, today.month}
  end
end
