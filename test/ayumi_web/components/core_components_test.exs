defmodule AyumiWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias AyumiWeb.CoreComponents

  describe "jst_datetime/1" do
    test "shows a UTC timestamp on the Japanese wall clock, to the minute" do
      html = render_component(&CoreComponents.jst_datetime/1, value: ~U[2026-06-01 15:30:45Z])

      assert html =~ ">2026-06-02 00:30</time>"
      # The machine-readable value keeps the exact instant.
      assert html =~ ~s(datetime="2026-06-01T15:30:45Z")
    end

    test "can include seconds" do
      html =
        render_component(&CoreComponents.jst_datetime/1,
          value: ~U[2026-06-01 15:30:45Z],
          seconds: true
        )

      assert html =~ ">2026-06-02 00:30:45</time>"
    end

    test "renders nothing for nil" do
      assert render_component(&CoreComponents.jst_datetime/1, value: nil) == ""
    end
  end
end
