defmodule Ayumi.Plans.AttendanceRecordTest do
  use ExUnit.Case, async: true

  alias Ayumi.Plans.AttendanceRecord

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

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

  defp get_change_or_field(cs, field) do
    Map.get(cs.changes, field, Map.get(cs.data, field))
  end
end
