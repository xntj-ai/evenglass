defmodule Evenglass.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Evenglass.Accounts` context.
  """

  import Ecto.Query

  alias Evenglass.Accounts
  alias Evenglass.Accounts.Scope

  def unique_pc_user_email, do: "pc_user#{System.unique_integer()}@example.com"
  def valid_pc_user_password, do: "hello world!"

  def valid_pc_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_pc_user_email()
    })
  end

  def unconfirmed_pc_user_fixture(attrs \\ %{}) do
    {:ok, pc_user} =
      attrs
      |> valid_pc_user_attributes()
      |> Accounts.register_pc_user()

    pc_user
  end

  def pc_user_fixture(attrs \\ %{}) do
    pc_user = unconfirmed_pc_user_fixture(attrs)

    token =
      extract_pc_user_token(fn url ->
        Accounts.deliver_login_instructions(pc_user, url)
      end)

    {:ok, {pc_user, _expired_tokens}} =
      Accounts.login_pc_user_by_magic_link(token)

    pc_user
  end

  def pc_user_scope_fixture do
    pc_user = pc_user_fixture()
    pc_user_scope_fixture(pc_user)
  end

  def pc_user_scope_fixture(pc_user) do
    Scope.for_pc_user(pc_user)
  end

  def set_password(pc_user) do
    {:ok, {pc_user, _expired_tokens}} =
      Accounts.update_pc_user_password(pc_user, %{password: valid_pc_user_password()})

    pc_user
  end

  @doc "Returns a fully-onboarded admin: confirmed email + password + TOTP enrolled."
  def admin_pc_user_fixture(attrs \\ %{}) do
    pc_user = pc_user_fixture(attrs) |> set_password()
    {:ok, pc_user} = Accounts.setup_totp(pc_user)
    otp = NimbleTOTP.verification_code(pc_user.totp_secret)
    {:ok, pc_user} = Accounts.confirm_totp(pc_user, otp)
    pc_user
  end

  def extract_pc_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Evenglass.Repo.update_all(
      from(t in Accounts.PCUserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_pc_user_magic_link_token(pc_user) do
    {encoded_token, pc_user_token} = Accounts.PCUserToken.build_email_token(pc_user, "login")
    Evenglass.Repo.insert!(pc_user_token)
    {encoded_token, pc_user_token.token}
  end

  def offset_pc_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Evenglass.Repo.update_all(
      from(ut in Accounts.PCUserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
