defmodule Ayumi.Plans.AttendanceRecordTest do
  use Ayumi.DataCase, async: false

  import Ayumi.PlansFixtures
  import Ayumi.AccountsFixtures

  alias Ayumi.Accounts.Scope
  alias Ayumi.Plans
  alias Ayumi.Plans.AttendanceRecord

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

  defp get_change_or_field(cs, field) do
    Map.get(cs.changes, field, Map.get(cs.data, field))
  end
end
