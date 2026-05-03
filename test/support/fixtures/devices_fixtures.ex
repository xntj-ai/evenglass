defmodule Evenglass.DevicesFixtures do
  @moduledoc """
  Fixtures for the Devices context — used by controller, channel, and
  context tests that need an enrolled device + signed device_token.
  """

  alias Evenglass.Devices
  alias Evenglass.Auth.Token

  def device_fixture(attrs \\ %{}) do
    Devices.create_device!(
      Enum.into(attrs, %{
        glasses_serial: "G-#{System.unique_integer([:positive])}"
      })
    )
  end

  @doc """
  Returns `%{device: device, token: device_token}` where the token is a
  freshly-signed Bearer credential keyed to the device's current jti.
  """
  def authenticated_device_fixture(attrs \\ %{}) do
    device = device_fixture(attrs)
    jti = "jti-#{System.unique_integer([:positive])}"
    device = Devices.set_jti!(device, jti)
    token = Token.sign_device_token(%{device_id: device.id, jti: jti})
    %{device: device, token: token}
  end
end
