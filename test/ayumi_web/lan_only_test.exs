defmodule AyumiWeb.LanOnlyTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias AyumiWeb.LanOnly

  describe "lan_or_local?/1" do
    test "allows IPv4 loopback" do
      assert LanOnly.lan_or_local?({127, 0, 0, 1})
      assert LanOnly.lan_or_local?({127, 0, 0, 53})
    end

    test "allows RFC1918 private ranges" do
      assert LanOnly.lan_or_local?({10, 0, 0, 5})
      assert LanOnly.lan_or_local?({172, 16, 0, 1})
      assert LanOnly.lan_or_local?({172, 31, 255, 254})
      assert LanOnly.lan_or_local?({192, 168, 1, 10})
    end

    test "allows IPv4 link-local" do
      assert LanOnly.lan_or_local?({169, 254, 1, 1})
    end

    test "allows IPv6 loopback, unique-local and link-local" do
      assert LanOnly.lan_or_local?({0, 0, 0, 0, 0, 0, 0, 1})
      assert LanOnly.lan_or_local?({0xFC00, 0, 0, 0, 0, 0, 0, 1})
      assert LanOnly.lan_or_local?({0xFD12, 0, 0, 0, 0, 0, 0, 1})
      assert LanOnly.lan_or_local?({0xFE80, 0, 0, 0, 0, 0, 0, 1})
    end

    test "allows IPv4-mapped IPv6 of a private address" do
      # ::ffff:192.168.1.1
      assert LanOnly.lan_or_local?({0, 0, 0, 0, 0, 0xFFFF, 0xC0A8, 0x0101})
    end

    test "rejects public IPv4" do
      refute LanOnly.lan_or_local?({8, 8, 8, 8})
      refute LanOnly.lan_or_local?({1, 1, 1, 1})
      refute LanOnly.lan_or_local?({11, 0, 0, 1})
      # just outside 172.16.0.0/12 on both sides
      refute LanOnly.lan_or_local?({172, 15, 255, 255})
      refute LanOnly.lan_or_local?({172, 32, 0, 1})
      refute LanOnly.lan_or_local?({192, 167, 0, 1})
    end

    test "rejects public IPv6" do
      # 2001:4860:: (Google)
      refute LanOnly.lan_or_local?({0x2001, 0x4860, 0, 0, 0, 0, 0, 0x8888})
    end

    test "rejects IPv4-mapped IPv6 of a public address" do
      # ::ffff:8.8.8.8
      refute LanOnly.lan_or_local?({0, 0, 0, 0, 0, 0xFFFF, 0x0808, 0x0808})
    end

    test "rejects non-IP values" do
      refute LanOnly.lan_or_local?(nil)
    end
  end

  describe "call/2 (Plug)" do
    test "passes a request from a LAN address" do
      conn =
        conn(:get, "/")
        |> Map.put(:remote_ip, {192, 168, 1, 5})
        |> LanOnly.call(LanOnly.init([]))

      refute conn.halted
    end

    test "rejects a request from a public address with 403" do
      conn =
        conn(:get, "/")
        |> Map.put(:remote_ip, {8, 8, 8, 8})
        |> LanOnly.call(LanOnly.init([]))

      assert conn.halted
      assert conn.status == 403
    end
  end

  describe "on_mount/4" do
    test "allows the dead render (socket not connected)" do
      assert {:cont, _socket} =
               LanOnly.on_mount(:default, %{}, %{}, %Phoenix.LiveView.Socket{})
    end
  end
end
