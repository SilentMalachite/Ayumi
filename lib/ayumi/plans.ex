defmodule Ayumi.Plans do
  @moduledoc """
  The Plans context: service users, support plans, goals, and (later) the
  append-only progress and phase-event logs. Current state is derived, never stored.
  """
  import Ecto.Query, warn: false
  alias Ayumi.Repo

  alias Ayumi.Plans.ServiceUser
end
