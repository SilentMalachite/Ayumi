defmodule AyumiWeb.LanOnly do
  @moduledoc """
  Restricts access to clients on the local machine or the facility LAN.

  Ayumi runs on a single office PC and is used over the LAN; it must not be
  reachable from the internet. This enforces that at the application layer,
  independent of how the endpoint is bound:

    * as a `Plug` (mounted in the endpoint) it returns 403 for any HTTP request
      whose remote IP is not loopback or a private/LAN address;
    * as an `on_mount` hook it applies the same check to LiveView WebSocket
      connections, which bypass the endpoint plug pipeline.

  Allowed: IPv4 loopback (127.0.0.0/8), RFC1918 private ranges (10.0.0.0/8,
  172.16.0.0/12, 192.168.0.0/16), link-local (169.254.0.0/16), IPv6 loopback
  (::1), unique-local (fc00::/7), link-local (fe80::/10), and IPv4-mapped IPv6
  of any of the above.

  This trusts `conn.remote_ip` / the socket peer address, which is correct
  because the app is served directly by Bandit with no reverse proxy. If a
  proxy is ever added, revisit this (the proxy would become the peer).
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if lan_or_local?(conn.remote_ip) do
      conn
    else
      conn
      |> send_resp(:forbidden, "Forbidden: access is limited to the local network.")
      |> halt()
    end
  end

  @doc """
  LiveView `on_mount` hook. Rejects connected sockets whose peer IP is not
  LAN/local. The dead (HTTP) render is already gated by the plug, and when the
  peer address is unavailable (e.g. in tests) the connection is allowed.
  """
  def on_mount(:default, _params, _session, socket) do
    if Phoenix.LiveView.connected?(socket) and blocked_peer?(socket) do
      {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
    else
      {:cont, socket}
    end
  end

  defp blocked_peer?(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: address} -> not lan_or_local?(address)
      _ -> false
    end
  end

  @doc "Returns true when the IP tuple is loopback or a private/LAN address."
  # IPv4
  def lan_or_local?({127, _, _, _}), do: true
  def lan_or_local?({10, _, _, _}), do: true
  def lan_or_local?({192, 168, _, _}), do: true
  def lan_or_local?({169, 254, _, _}), do: true
  def lan_or_local?({172, b, _, _}) when b >= 16 and b <= 31, do: true
  def lan_or_local?({_, _, _, _}), do: false

  # IPv6
  def lan_or_local?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  # IPv4-mapped IPv6 (::ffff:a.b.c.d) — classify the embedded IPv4
  def lan_or_local?({0, 0, 0, 0, 0, 0xFFFF, g, h}) do
    lan_or_local?({div(g, 256), rem(g, 256), div(h, 256), rem(h, 256)})
  end

  # unique-local fc00::/7 -> first hextet 0xfc00..0xfdff
  def lan_or_local?({a, _, _, _, _, _, _, _}) when a >= 0xFC00 and a <= 0xFDFF, do: true
  # link-local fe80::/10 -> first hextet 0xfe80..0xfebf
  def lan_or_local?({a, _, _, _, _, _, _, _}) when a >= 0xFE80 and a <= 0xFEBF, do: true
  def lan_or_local?({_, _, _, _, _, _, _, _}), do: false

  def lan_or_local?(_), do: false
end
