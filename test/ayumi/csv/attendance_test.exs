defmodule Ayumi.CSV.AttendanceTest do
  use ExUnit.Case, async: true

  alias Ayumi.Accounts.User
  alias Ayumi.CSV.Attendance
  alias Ayumi.Plans.{AttendanceRecord, ServiceUser}

  @headers [
    "利用者ID",
    "氏名",
    "利用日",
    "曜",
    "提供形態",
    "開始",
    "終了",
    "送迎(往)",
    "送迎(復)",
    "備考",
    "記録者",
    "記録日時(日本時間)",
    "記録ID"
  ]

  defp record(attrs) do
    struct!(
      %AttendanceRecord{
        id: 7,
        service_user_id: 3,
        service_user: %ServiceUser{id: 3, name: "山田 太郎"},
        service_date: ~D[2026-09-14],
        provision_type: :commute,
        pickup: true,
        dropoff: false,
        start_time: ~T[09:00:00],
        end_time: ~T[15:30:00],
        note: "良好",
        recorded_by: %User{name: "支援 花子", email: "hanako@example.com"},
        recorded_at: ~U[2026-09-14 07:00:00Z]
      },
      attrs
    )
  end

  test "headers/0 follows the printed sheet's column order" do
    assert Attendance.headers() == @headers
  end

  test "dump/1 renders one row per record, aligned with the headers" do
    assert Attendance.dump([record(%{})]) == [
             [
               "3",
               "山田 太郎",
               "2026-09-14",
               "月",
               "通所",
               "09:00",
               "15:30",
               "○",
               "",
               "良好",
               "支援 花子",
               "2026-09-14 16:00:00",
               "7"
             ]
           ]
  end

  test "dump/1 leaves missing times and notes blank" do
    [row] =
      Attendance.dump([
        record(%{
          provision_type: :absence,
          pickup: false,
          start_time: nil,
          end_time: nil,
          note: nil
        })
      ])

    assert Enum.slice(row, 4..9) == ["欠席", "", "", "", "", ""]
  end

  test "dump/1 falls back to the recorder's email when the name is blank" do
    [row] = Attendance.dump([record(%{recorded_by: %User{name: nil, email: "a@example.com"}})])

    assert Enum.at(row, 10) == "a@example.com"
  end

  test "every row has exactly as many cells as there are headers" do
    [row] = Attendance.dump([record(%{})])

    assert length(row) == length(Attendance.headers())
  end
end
