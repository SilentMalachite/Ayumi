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

  describe "required_headers/0" do
    test "lists the columns the import reads — every one must be present" do
      assert Attendance.required_headers() ==
               ~w[利用者ID 氏名 利用日 提供形態 開始 終了 送迎(往) 送迎(復) 備考]
    end
  end

  describe "parse/1" do
    @cells %{
      "利用者ID" => "3",
      "氏名" => "山田 太郎",
      "利用日" => "2026/9/14",
      "曜" => "月",
      "提供形態" => "通所",
      "開始" => "9:00",
      "終了" => "15:30",
      "送迎(往)" => "○",
      "送迎(復)" => "",
      "備考" => "良好",
      "記録者" => "無視される",
      "記録日時(日本時間)" => "無視される",
      "記録ID" => "999"
    }

    test "turns a row's cells into attrs, ignoring the export-only columns" do
      assert Attendance.parse(@cells) ==
               {:ok,
                %{
                  service_user_id: 3,
                  service_user_name: "山田 太郎",
                  service_date: ~D[2026-09-14],
                  provision_type: :commute,
                  start_time: ~T[09:00:00],
                  end_time: ~T[15:30:00],
                  pickup: true,
                  dropoff: false,
                  note: "良好"
                }}
    end

    test "reads back exactly what dump/1 wrote" do
      [row] = Attendance.dump([record(%{})])
      cells = Attendance.headers() |> Enum.zip(row) |> Map.new()

      assert {:ok, attrs} = Attendance.parse(cells)
      assert attrs.service_user_id == 3
      assert attrs.service_date == ~D[2026-09-14]
      assert attrs.provision_type == :commute
      assert {attrs.start_time, attrs.end_time} == {~T[09:00:00], ~T[15:30:00]}
      assert {attrs.pickup, attrs.dropoff, attrs.note} == {true, false, "良好"}
    end

    test "blank optional cells become nil / false" do
      cells =
        Map.merge(@cells, %{"利用者ID" => "", "開始" => "", "終了" => "", "送迎(往)" => "", "備考" => ""})

      assert {:ok, attrs} = Attendance.parse(cells)
      assert attrs.service_user_id == nil

      assert {attrs.start_time, attrs.end_time, attrs.pickup, attrs.note} ==
               {nil, nil, false, nil}
    end

    test "collects every unreadable or missing cell, in column order" do
      cells = Map.merge(@cells, %{"利用日" => "", "提供形態" => "出席", "開始" => "9時"})

      assert {:error, errors} = Attendance.parse(cells)
      assert Enum.map(errors, & &1.column) == ["利用日", "提供形態", "開始"]
      assert [%{message: "入力してください"}, %{message: enum}, %{message: time}] = errors
      assert enum =~ "通所"
      assert time =~ "時刻"
    end
  end

  test "header_for/1 maps an attrs key back to its column header" do
    assert Attendance.header_for(:end_time) == "終了"
    assert Attendance.header_for(:service_date) == "利用日"
    assert Attendance.header_for(:unknown) == nil
  end
end
