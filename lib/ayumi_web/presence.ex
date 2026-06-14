defmodule AyumiWeb.Presence do
  @moduledoc """
  Tracks which staff currently have a body-record edit form open, so the UI can
  warn about concurrent edits. Advisory only — the optimistic lock in
  `Ayumi.Plans` is what actually prevents lost updates. Runs on the local
  `Ayumi.PubSub`; no external dependency.
  """
  use Phoenix.Presence,
    otp_app: :ayumi,
    pubsub_server: Ayumi.PubSub

  @doc """
  PubSub/Presence topic for the edit form of a given body record, e.g.
  `editing_topic(:service_user, 5) == "editing:service_user:5"`.
  """
  def editing_topic(kind, id) when is_atom(kind), do: "editing:#{kind}:#{id}"
end
