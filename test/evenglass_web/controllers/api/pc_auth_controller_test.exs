defmodule EvenglassWeb.Api.PcAuthControllerTest do
  use EvenglassWeb.ConnCase, async: false

  import Evenglass.AccountsFixtures

  alias Evenglass.Auth.Token

  describe "POST /api/pc/socket-token" do
    test "returns a usable :pc_admin channel_token for an authenticated admin", %{conn: conn} do
      pc_user = admin_pc_user_fixture()
      conn = log_in_pc_user(conn, pc_user)

      conn = post(conn, ~p"/api/pc/socket-token")
      body = json_response(conn, 200)

      assert body["expires_in"] == Token.channel_max_age()
      assert is_binary(body["channel_token"])

      pc_user_id = pc_user.id

      assert {:ok, %{pc_user_id: ^pc_user_id, role: :pc_admin}} =
               Token.verify_channel_token(body["channel_token"])
    end

    test "rejects with 401 when no admin session is present", %{conn: conn} do
      conn = post(conn, ~p"/api/pc/socket-token")
      body = json_response(conn, 401)
      assert body["error"] == "unauthorized"
    end

    test "rejects with 401 when admin has no TOTP enrolled", %{conn: conn} do
      pc_user = pc_user_fixture() |> set_password()
      conn = log_in_pc_user(conn, pc_user)

      conn = post(conn, ~p"/api/pc/socket-token")
      body = json_response(conn, 401)
      assert body["error"] == "totp_required"
    end
  end
end
