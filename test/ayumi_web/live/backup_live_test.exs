defmodule AyumiWeb.BackupLiveTest do
  use AyumiWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ayumi.AccountsFixtures

  describe "GET /admin/backup" do
    test "redirects non-manager users", %{conn: conn} do
      user = staff_fixture()
      conn = log_in_user(conn, user)
      {:error, {:redirect, redirect}} = live(conn, ~p"/admin/backup")
      assert redirect.to == "/"
    end

    test "renders for manager users", %{conn: conn} do
      user = manager_fixture()
      conn = log_in_user(conn, user)
      {:ok, _lv, html} = live(conn, ~p"/admin/backup")
      assert html =~ "バックアップ"
    end
  end

  describe "backup execution" do
    setup %{conn: conn} do
      user = manager_fixture()
      conn = log_in_user(conn, user)
      %{conn: conn}
    end

    @tag :tmp_dir
    test "creates backup successfully", %{conn: conn, tmp_dir: tmp_dir} do
      {:ok, lv, _html} = live(conn, ~p"/admin/backup")

      html =
        lv
        |> form("#backup-form", %{dest_dir: tmp_dir})
        |> render_submit()

      assert html =~ "バックアップが完了しました" or html =~ "ayumi_backup_"
    end

    test "shows error for invalid directory", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/backup")

      html =
        lv
        |> form("#backup-form", %{dest_dir: "/nonexistent/path/#{System.unique_integer()}"})
        |> render_submit()

      assert html =~ "存在しない" or html =~ "失敗"
    end

    @tag :tmp_dir
    test "成功時に完了フラッシュが表示される", %{conn: conn, tmp_dir: tmp_dir} do
      {:ok, lv, _html} = live(conn, ~p"/admin/backup")

      html =
        lv
        |> form("#backup-form", %{dest_dir: tmp_dir})
        |> render_submit()

      # インラインは「バックアップ完了」。フラッシュ固有の文言で判定する。
      assert html =~ "バックアップが完了しました"
    end
  end
end
