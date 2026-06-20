defmodule Ayumi.Plans.AttendanceRecordTest do
  use Ayumi.DataCase, async: false

  import Ayumi.PlansFixtures
  import Ayumi.AccountsFixtures

  alias Ayumi.Accounts.Scope
  alias Ayumi.Plans
  alias Ayumi.Plans.{AttendanceRecord, AttendanceSheet}

  describe "changeset/2" do
    test "with valid minimum attrs is valid" do
      attrs = %{
        service_user_id: 1,
        service_date: ~D[2026-06-01],
        provision_type: :commute
      }

      cs = AttendanceRecord.changeset(%AttendanceRecord{}, attrs)
      assert cs.valid?
      assert get_change_or_field(cs, :pickup) == false
      assert get_change_or_field(cs, :dropoff) == false
    end

    test "requires service_user_id / service_date / provision_type" do
      cs = AttendanceRecord.changeset(%AttendanceRecord{}, %{})
      errors = errors_on(cs)
      assert errors[:service_user_id]
      assert errors[:service_date]
      assert errors[:provision_type]
    end

    test "rejects provision_type outside of the enum" do
      cs =
        AttendanceRecord.changeset(%AttendanceRecord{}, %{
          service_user_id: 1,
          service_date: ~D[2026-06-01],
          provision_type: :bogus
        })

      refute cs.valid?
      assert errors_on(cs)[:provision_type]
    end

    test "allows both start_time and end_time nil" do
      cs =
        AttendanceRecord.changeset(%AttendanceRecord{}, %{
          service_user_id: 1,
          service_date: ~D[2026-06-01],
          provision_type: :commute
        })

      assert cs.valid?
    end

    test "rejects end_time on or before start_time" do
      cs =
        AttendanceRecord.changeset(%AttendanceRecord{}, %{
          service_user_id: 1,
          service_date: ~D[2026-06-01],
          provision_type: :commute,
          start_time: ~T[10:00:00],
          end_time: ~T[10:00:00]
        })

      refute cs.valid?
      assert errors_on(cs)[:end_time] == ["終了時刻は開始時刻より後にしてください"]
    end

    test "accepts pickup / dropoff true" do
      cs =
        AttendanceRecord.changeset(%AttendanceRecord{}, %{
          service_user_id: 1,
          service_date: ~D[2026-06-01],
          provision_type: :commute,
          pickup: true,
          dropoff: true
        })

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :pickup) == true
      assert Ecto.Changeset.get_field(cs, :dropoff) == true
    end
  end

  describe "put_audit/3" do
    test "puts recorded_by_id and recorded_at" do
      cs =
        %AttendanceRecord{}
        |> AttendanceRecord.changeset(%{
          service_user_id: 1,
          service_date: ~D[2026-06-01],
          provision_type: :commute
        })
        |> AttendanceRecord.put_audit(42, ~U[2026-06-21 12:00:00Z])

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :recorded_by_id) == 42
      assert Ecto.Changeset.get_field(cs, :recorded_at) == ~U[2026-06-21 12:00:00Z]
    end
  end

  describe "create_attendance_record/2" do
    test "inserts a record with scope-derived audit fields" do
      su = service_user_fixture()
      staff = user_fixture()
      scope = Scope.for_user(staff)

      assert {:ok, %AttendanceRecord{} = rec} =
               Plans.create_attendance_record(scope, %{
                 service_user_id: su.id,
                 service_date: ~D[2026-06-01],
                 provision_type: :commute
               })

      assert rec.service_user_id == su.id
      assert rec.provision_type == :commute
      assert rec.recorded_by_id == staff.id
      assert %DateTime{} = rec.recorded_at
    end

    test "allows recording for a withdrawn service user (intentional diff vs support_record)" do
      su = service_user_fixture(%{name: "退所者", enrollment_status: :withdrawn})
      scope = Scope.for_user(user_fixture())

      assert {:ok, _rec} =
               Plans.create_attendance_record(scope, %{
                 service_user_id: su.id,
                 service_date: ~D[2026-06-01],
                 provision_type: :commute
               })
    end

    test "returns FK error changeset for an unknown service_user_id" do
      scope = Scope.for_user(user_fixture())

      assert {:error, cs} =
               Plans.create_attendance_record(scope, %{
                 service_user_id: -1,
                 service_date: ~D[2026-06-01],
                 provision_type: :commute
               })

      assert errors_on(cs)[:service_user_id]
    end
  end

  describe "change_attendance_record/2" do
    test "returns a changeset for empty attrs" do
      cs = Plans.change_attendance_record(%AttendanceRecord{})
      assert %Ecto.Changeset{} = cs
    end
  end

  describe "list_attendance_records/3" do
    test "returns only rows in the requested month, oldest-first by id" do
      su = service_user_fixture()
      scope = Scope.for_user(user_fixture())

      {:ok, before_rec} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-05-31],
          provision_type: :commute
        })

      {:ok, jun1} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-06-01],
          provision_type: :commute
        })

      {:ok, jun30} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-06-30],
          provision_type: :absence
        })

      {:ok, after_rec} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-07-01],
          provision_type: :commute
        })

      ids = Plans.list_attendance_records(su.id, 2026, 6) |> Enum.map(& &1.id)
      assert ids == [jun1.id, jun30.id]
      refute before_rec.id in ids
      refute after_rec.id in ids
    end

    test "scopes by service_user_id" do
      su1 = service_user_fixture()
      su2 = service_user_fixture(%{name: "別の人", name_kana: "べつのひと"})
      scope = Scope.for_user(user_fixture())

      {:ok, _} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su1.id,
          service_date: ~D[2026-06-10],
          provision_type: :commute
        })

      {:ok, _} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su2.id,
          service_date: ~D[2026-06-10],
          provision_type: :commute
        })

      assert length(Plans.list_attendance_records(su1.id, 2026, 6)) == 1
      assert length(Plans.list_attendance_records(su2.id, 2026, 6)) == 1
    end
  end

  describe "build_attendance_sheet/3" do
    setup do
      su = service_user_fixture()
      scope = Scope.for_user(user_fixture())
      %{su: su, scope: scope}
    end

    test "lines cover every day of a 30-day month", %{su: su} do
      sheet = Plans.build_attendance_sheet(su.id, 2026, 6)
      assert %AttendanceSheet{year: 2026, month: 6, service_user_id: su_id} = sheet
      assert su_id == su.id
      assert length(sheet.lines) == 30
      assert hd(sheet.lines).date == ~D[2026-06-01]
      assert List.last(sheet.lines).date == ~D[2026-06-30]
    end

    test "lines cover every day of a 31-day month", %{su: su} do
      sheet = Plans.build_attendance_sheet(su.id, 2026, 7)
      assert length(sheet.lines) == 31
    end

    test "lines cover every day of February (non-leap 2026)", %{su: su} do
      sheet = Plans.build_attendance_sheet(su.id, 2026, 2)
      assert length(sheet.lines) == 28
    end

    test "days without rows have record: nil and do not count toward totals", %{su: su} do
      sheet = Plans.build_attendance_sheet(su.id, 2026, 6)
      assert Enum.all?(sheet.lines, &is_nil(&1.record))

      assert sheet.totals == %{
               billable_days: 0,
               offsite_days: 0,
               pickup_count: 0,
               dropoff_count: 0,
               absence_support_count: 0
             }
    end

    test "later id wins for the same service_date (correction semantics)",
         %{su: su, scope: scope} do
      {:ok, _first} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-06-15],
          provision_type: :absence
        })

      {:ok, correction} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-06-15],
          provision_type: :commute
        })

      sheet = Plans.build_attendance_sheet(su.id, 2026, 6)
      jun15 = Enum.find(sheet.lines, &(&1.date == ~D[2026-06-15]))
      assert jun15.record.id == correction.id
      assert jun15.record.provision_type == :commute
    end

    test "billable_days counts only commute / offsite_work / offsite_support",
         %{su: su, scope: scope} do
      for {date, type} <- [
            {~D[2026-06-01], :commute},
            {~D[2026-06-02], :offsite_work},
            {~D[2026-06-03], :offsite_support},
            {~D[2026-06-04], :absence},
            {~D[2026-06-05], :absence_support}
          ] do
        {:ok, _} =
          Plans.create_attendance_record(scope, %{
            service_user_id: su.id,
            service_date: date,
            provision_type: type
          })
      end

      sheet = Plans.build_attendance_sheet(su.id, 2026, 6)
      assert sheet.totals.billable_days == 3
      assert sheet.totals.offsite_days == 2
      assert sheet.totals.absence_support_count == 1
    end

    test "pickup_count and dropoff_count count adopted rows only",
         %{su: su, scope: scope} do
      {:ok, _} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-06-01],
          provision_type: :commute,
          pickup: true,
          dropoff: true
        })

      {:ok, _} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-06-02],
          provision_type: :commute,
          pickup: true,
          dropoff: false
        })

      sheet = Plans.build_attendance_sheet(su.id, 2026, 6)
      assert sheet.totals.pickup_count == 2
      assert sheet.totals.dropoff_count == 1
    end

    test "correction overwrites prior pickup/dropoff in counts",
         %{su: su, scope: scope} do
      {:ok, _} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-06-10],
          provision_type: :commute,
          pickup: true,
          dropoff: true
        })

      {:ok, _} =
        Plans.create_attendance_record(scope, %{
          service_user_id: su.id,
          service_date: ~D[2026-06-10],
          provision_type: :absence,
          pickup: false,
          dropoff: false
        })

      sheet = Plans.build_attendance_sheet(su.id, 2026, 6)
      assert sheet.totals.pickup_count == 0
      assert sheet.totals.dropoff_count == 0
      assert sheet.totals.billable_days == 0
    end
  end

  defp get_change_or_field(cs, field) do
    Map.get(cs.changes, field, Map.get(cs.data, field))
  end
end
