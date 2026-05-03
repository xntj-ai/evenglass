defmodule EvenglassWeb.Admin.NewDeviceLiveTest do
  use EvenglassWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Evenglass.AccountsFixtures

  describe "GET /admin/devices/new" do
    test "renders the form for an enrolled admin", %{conn: conn} do
      conn = log_in_pc_user(conn, admin_pc_user_fixture())

      {:ok, _lv, html} = live(conn, ~p"/admin/devices/new")

      assert html =~ "New device"
      assert html =~ "Generate enrollment code"
      assert html =~ "Glasses serial"
    end

    test "submitting the form renders a 6-digit code", %{conn: conn} do
      conn = log_in_pc_user(conn, admin_pc_user_fixture())

      {:ok, lv, _} = live(conn, ~p"/admin/devices/new")

      html = lv |> form("form", glasses_serial: "G2-TEST-001") |> render_submit()

      assert Regex.match?(~r/\b\d{6}\b/, html)
      assert html =~ "Read this to the operator"
      assert html =~ "G2-TEST-001"
    end

    test "redirects unauthenticated visitors to log-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/pc_users/log-in"}}} =
               live(conn, ~p"/admin/devices/new")
    end
  end
end
