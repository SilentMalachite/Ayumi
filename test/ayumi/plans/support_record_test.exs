defmodule Ayumi.Plans.SupportRecordTest do
  use Ayumi.DataCase, async: false

  import Ayumi.AccountsFixtures
  import Ayumi.PlansFixtures

  alias Ayumi.Plans
  alias Ayumi.Plans.SupportRecord

  @attrs %{service_user_id: 1, content: "午前の作業に集中できた", category: :work}

  describe "changeset/2 and put_audit/3 — support_date" do
    test "casts an explicit support date" do
      changeset =
        SupportRecord.changeset(%SupportRecord{}, Map.put(@attrs, :support_date, "2026-08-20"))

      assert changeset.valid?
      assert get_change(changeset, :support_date) == ~D[2026-08-20]
    end

    test "defaults to the JST date on which it was recorded" do
      changeset = SupportRecord.changeset(%SupportRecord{}, @attrs)

      # 2026-08-31 15:00 UTC is already 2026-09-01 in Japan.
      assert changeset
             |> SupportRecord.put_audit(1, ~U[2026-08-31 15:00:00Z])
             |> get_field(:support_date) == ~D[2026-09-01]

      assert changeset
             |> SupportRecord.put_audit(1, ~U[2026-08-31 14:59:59Z])
             |> get_field(:support_date) == ~D[2026-08-31]
    end

    test "keeps an explicit past date, and accepts the recording day itself" do
      for date <- [~D[2026-08-20], ~D[2026-09-01]] do
        changeset =
          %SupportRecord{}
          |> SupportRecord.changeset(Map.put(@attrs, :support_date, date))
          |> SupportRecord.put_audit(1, ~U[2026-08-31 15:00:00Z])

        assert changeset.valid?
        assert get_field(changeset, :support_date) == date
      end
    end

    test "rejects a support date after the JST day it was recorded" do
      changeset =
        %SupportRecord{}
        |> SupportRecord.changeset(Map.put(@attrs, :support_date, ~D[2026-09-02]))
        |> SupportRecord.put_audit(1, ~U[2026-08-31 15:00:00Z])

      refute changeset.valid?
      assert errors_on(changeset).support_date == ["未来の日付は指定できません"]
    end
  end

  describe "create_support_record/2" do
    setup do
      %{scope: user_scope_fixture(), su: service_user_fixture()}
    end

    test "stores the given support date", %{scope: scope, su: su} do
      assert {:ok, record} =
               Plans.create_support_record(scope, %{
                 service_user_id: su.id,
                 content: "先週の面談",
                 category: :interview,
                 support_date: ~D[2026-06-01]
               })

      assert record.support_date == ~D[2026-06-01]
      assert DateTime.diff(DateTime.utc_now(), record.recorded_at) < 60
    end

    test "defaults the support date to today in Japan", %{scope: scope, su: su} do
      assert {:ok, record} =
               Plans.create_support_record(scope, %{
                 service_user_id: su.id,
                 content: "今日の記録",
                 category: :work
               })

      assert record.support_date == Ayumi.JST.today()
    end

    test "rejects a future support date", %{scope: scope, su: su} do
      assert {:error, changeset} =
               Plans.create_support_record(scope, %{
                 service_user_id: su.id,
                 content: "未来",
                 category: :work,
                 support_date: Date.add(Ayumi.JST.today(), 1)
               })

      assert errors_on(changeset).support_date == ["未来の日付は指定できません"]
    end
  end

  describe "listing by support date" do
    setup do
      %{scope: user_scope_fixture(), su: service_user_fixture()}
    end

    test "list_support_records/2 filters :from/:to on the support date, inclusive", %{
      scope: scope,
      su: su
    } do
      for date <- [~D[2026-06-09], ~D[2026-06-10], ~D[2026-06-20], ~D[2026-06-21]] do
        support_record_fixture(%{
          service_user_id: su.id,
          support_date: date,
          content: Date.to_iso8601(date)
        })
      end

      records = Plans.list_support_records(scope, from: ~D[2026-06-10], to: ~D[2026-06-20])

      assert Enum.map(records, & &1.content) == ["2026-06-20", "2026-06-10"]
    end

    test "list_support_records/2 orders by support date, newest first, then by recording", %{
      scope: scope,
      su: su
    } do
      # Entered in this order; the back-dated record sorts by when the support happened.
      recent = support_record_fixture(%{service_user_id: su.id, support_date: ~D[2026-06-10]})
      backdated = support_record_fixture(%{service_user_id: su.id, support_date: ~D[2026-06-01]})
      same_day = support_record_fixture(%{service_user_id: su.id, support_date: ~D[2026-06-10]})

      assert scope |> Plans.list_support_records() |> Enum.map(& &1.id) ==
               [same_day.id, recent.id, backdated.id]
    end

    test "list_recent_support_records/2 orders by support date too", %{su: su} do
      recent = support_record_fixture(%{service_user_id: su.id, support_date: ~D[2026-06-10]})
      backdated = support_record_fixture(%{service_user_id: su.id, support_date: ~D[2026-06-01]})

      assert su.id |> Plans.list_recent_support_records() |> Enum.map(& &1.id) ==
               [recent.id, backdated.id]
    end
  end
end
