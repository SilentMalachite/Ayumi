defmodule AyumiWeb.PresenceTest do
  use ExUnit.Case, async: true

  test "editing_topic/2 builds a per-record topic" do
    assert AyumiWeb.Presence.editing_topic(:service_user, 7) == "editing:service_user:7"
  end
end
