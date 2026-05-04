defmodule Evenglass.Auth.Token do
  @moduledoc """
  Phoenix.Token-based device & channel token signing/verification.

  Two token kinds:

    * `device_token` (90d, salt: `:device_token_salt`) — Bearer credential for
      Hub App → Phoenix REST. Carries `%{device_id, jti}`. The `jti` is rotated
      on every refresh; revocation is implemented by clearing the device's
      stored `jti` so any old token whose `jti` mismatches is rejected.

    * `channel_token` (2h, salt: `:channel_token_salt`) — short-lived credential
      for WSS connect. Two variants:
        - `:device` role: issued by `/api/g2/socket-token` after device_token
          verification. Payload `%{device_id, role: :device}`.
        - `:pc_admin` role: issued by `/api/pc/socket-token` after PC admin
          session + 2FA verification. Payload `%{pc_user_id, role: :pc_admin}`.
          PC admins may join any `g2:device:<id>` topic (monitoring/control).

  Salts are configured per env (`config/dev.exs`, `config/runtime.exs`).
  """

  alias EvenglassWeb.Endpoint

  @device_max_age 90 * 24 * 60 * 60
  @channel_max_age 2 * 60 * 60

  def device_max_age, do: @device_max_age
  def channel_max_age, do: @channel_max_age

  ## Device tokens ───────────────────────────────────────────────────────────

  def sign_device_token(%{device_id: id, jti: jti})
      when is_binary(id) and is_binary(jti) do
    Phoenix.Token.sign(Endpoint, salt(:device), %{device_id: id, jti: jti})
  end

  def verify_device_token(token) when is_binary(token) do
    Phoenix.Token.verify(Endpoint, salt(:device), token, max_age: @device_max_age)
  end

  ## Channel tokens ──────────────────────────────────────────────────────────

  def sign_channel_token(%{device_id: id, role: :device}) when is_binary(id) do
    Phoenix.Token.sign(Endpoint, salt(:channel), %{device_id: id, role: :device})
  end

  def sign_channel_token(%{pc_user_id: uid, role: :pc_admin}) when is_binary(uid) do
    Phoenix.Token.sign(Endpoint, salt(:channel), %{pc_user_id: uid, role: :pc_admin})
  end

  def verify_channel_token(token) when is_binary(token) do
    Phoenix.Token.verify(Endpoint, salt(:channel), token, max_age: @channel_max_age)
  end

  ## Helpers ─────────────────────────────────────────────────────────────────

  defp salt(:device), do: Application.fetch_env!(:evenglass, :device_token_salt)
  defp salt(:channel), do: Application.fetch_env!(:evenglass, :channel_token_salt)
end
