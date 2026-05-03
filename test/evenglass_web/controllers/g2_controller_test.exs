defmodule EvenglassWeb.G2ControllerTest do
  use EvenglassWeb.ConnCase, async: false

  import Ecto.Query
  import Evenglass.DevicesFixtures

  alias Evenglass.{Events, Repo}
  alias Evenglass.Events.Event

  describe "POST /api/g2/events idempotency" do
    setup do
      authenticated_device_fixture()
    end

    test "returns the same event on retry with the same Idempotency-Key", %{
      conn: conn,
      token: token
    } do
      key = "ulid-test-#{System.unique_integer([:positive])}"

      first =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("idempotency-key", key)
        |> post(~p"/api/g2/events", %{"type" => "tap", "payload" => %{"button" => "right"}})

      assert %{"id" => id1} = json_response(first, 201)

      second =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("idempotency-key", key)
        |> post(~p"/api/g2/events", %{"type" => "tap", "payload" => %{"button" => "right"}})

      assert %{"id" => id2} = json_response(second, 201)

      assert id1 == id2

      # Only one row in the DB, even though we POSTed twice.
      assert 1 ==
               Repo.aggregate(from(e in Event, where: e.idempotency_key == ^key), :count)
    end

    test "different Idempotency-Keys create different events", %{conn: conn, token: token} do
      base = build_conn() |> put_req_header("authorization", "Bearer #{token}")

      first =
        base
        |> put_req_header("idempotency-key", "key-#{System.unique_integer([:positive])}")
        |> post(~p"/api/g2/events", %{"type" => "tap"})

      second =
        base
        |> put_req_header("idempotency-key", "key-#{System.unique_integer([:positive])}")
        |> post(~p"/api/g2/events", %{"type" => "tap"})

      _ = conn
      assert json_response(first, 201)["id"] != json_response(second, 201)["id"]
    end

    test "no Idempotency-Key behaves as before — every POST creates a new event", %{
      conn: conn,
      token: token
    } do
      base = build_conn() |> put_req_header("authorization", "Bearer #{token}")

      first = post(base, ~p"/api/g2/events", %{"type" => "tap"})
      second = post(base, ~p"/api/g2/events", %{"type" => "tap"})

      _ = conn
      assert json_response(first, 201)["id"] != json_response(second, 201)["id"]
    end

    test "malformed Idempotency-Key (e.g. spaces) is treated as no key", %{
      conn: conn,
      token: token
    } do
      base =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("idempotency-key", "has spaces and stuff")

      first = post(base, ~p"/api/g2/events", %{"type" => "tap"})
      second = post(base, ~p"/api/g2/events", %{"type" => "tap"})

      _ = conn
      # Neither row stored a key, so the second POST does not collapse.
      assert json_response(first, 201)["id"] != json_response(second, 201)["id"]
    end
  end

  describe "Events.create_event_idempotent!/1" do
    test "returns existing row on duplicate insert race" do
      device = device_fixture()
      session = Evenglass.Sessions.touch_session_by_device_id!(device.id)
      key = "race-#{System.unique_integer([:positive])}"

      attrs = %{
        session_id: session.id,
        direction: "up",
        type: "ping",
        idempotency_key: key
      }

      e1 = Events.create_event_idempotent!(attrs)
      e2 = Events.create_event_idempotent!(attrs)

      assert e1.id == e2.id
    end
  end
end
