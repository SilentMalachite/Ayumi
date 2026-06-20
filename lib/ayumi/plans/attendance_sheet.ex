defmodule Ayumi.Plans.AttendanceSheet do
  @moduledoc "1利用者・1か月の実績記録票（ログから導出した値。保存しない）。"
  @enforce_keys [:service_user_id, :year, :month, :lines, :totals]
  defstruct [:service_user_id, :year, :month, :lines, :totals]

  @type line :: %{date: Date.t(), record: Ayumi.Plans.AttendanceRecord.t() | nil}
  @type totals :: %{
          billable_days: non_neg_integer(),
          offsite_days: non_neg_integer(),
          pickup_count: non_neg_integer(),
          dropoff_count: non_neg_integer(),
          absence_support_count: non_neg_integer()
        }
  @type t :: %__MODULE__{
          service_user_id: integer(),
          year: integer(),
          month: integer(),
          lines: [line()],
          totals: totals()
        }
end
