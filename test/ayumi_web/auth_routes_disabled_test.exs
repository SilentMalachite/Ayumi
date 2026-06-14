defmodule AyumiWeb.AuthRoutesDisabledTest do
  @moduledoc """
  Account creation is offline-only (mix ayumi.create_user / seeds), and email
  magic links don't work without an email provider. The public self-registration
  and magic-link routes are therefore removed; these tests lock that in.
  """
  use AyumiWeb.ConnCase

  test "public registration route is disabled", %{conn: conn} do
    assert get(conn, "/users/register").status == 404
  end

  test "magic-link confirmation route is disabled", %{conn: conn} do
    assert get(conn, "/users/log-in/some-token").status == 404
  end
end
