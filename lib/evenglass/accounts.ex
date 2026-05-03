defmodule Evenglass.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Evenglass.Repo

  alias Evenglass.Accounts.{PCUser, PCUserToken, PCUserNotifier}

  ## Database getters

  @doc """
  Gets a pc_user by email.

  ## Examples

      iex> get_pc_user_by_email("foo@example.com")
      %PCUser{}

      iex> get_pc_user_by_email("unknown@example.com")
      nil

  """
  def get_pc_user_by_email(email) when is_binary(email) do
    Repo.get_by(PCUser, email: normalize_email(email))
  end

  @doc """
  Gets a pc_user by email and password.

  ## Examples

      iex> get_pc_user_by_email_and_password("foo@example.com", "correct_password")
      %PCUser{}

      iex> get_pc_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_pc_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    pc_user = Repo.get_by(PCUser, email: normalize_email(email))
    if PCUser.valid_password?(pc_user, password), do: pc_user
  end

  # Email comparison is case-insensitive; the same normalization is applied
  # in PCUser.validate_email so DB rows are stored canonical.
  defp normalize_email(email) when is_binary(email) do
    email |> String.trim() |> String.downcase()
  end

  @doc """
  Gets a single pc_user.

  Raises `Ecto.NoResultsError` if the PCUser does not exist.

  ## Examples

      iex> get_pc_user!(123)
      %PCUser{}

      iex> get_pc_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_pc_user!(id), do: Repo.get!(PCUser, id)

  ## Pc user registration

  @doc """
  Registers a pc_user.

  ## Examples

      iex> register_pc_user(%{field: value})
      {:ok, %PCUser{}}

      iex> register_pc_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_pc_user(attrs) do
    %PCUser{}
    |> PCUser.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the pc_user is in sudo mode.

  The pc_user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(pc_user, minutes \\ -20)

  def sudo_mode?(%PCUser{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_pc_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the pc_user email.

  See `Evenglass.Accounts.PCUser.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_pc_user_email(pc_user)
      %Ecto.Changeset{data: %PCUser{}}

  """
  def change_pc_user_email(pc_user, attrs \\ %{}, opts \\ []) do
    PCUser.email_changeset(pc_user, attrs, opts)
  end

  @doc """
  Updates the pc_user email using the given token.

  If the token matches, the pc_user email is updated and the token is deleted.
  """
  def update_pc_user_email(pc_user, token) do
    context = "change:#{pc_user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- PCUserToken.verify_change_email_token_query(token, context),
           %PCUserToken{sent_to: email} <- Repo.one(query),
           {:ok, pc_user} <- Repo.update(PCUser.email_changeset(pc_user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(
               from(PCUserToken, where: [pc_user_id: ^pc_user.id, context: ^context])
             ) do
        {:ok, pc_user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the pc_user password.

  See `Evenglass.Accounts.PCUser.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_pc_user_password(pc_user)
      %Ecto.Changeset{data: %PCUser{}}

  """
  def change_pc_user_password(pc_user, attrs \\ %{}, opts \\ []) do
    PCUser.password_changeset(pc_user, attrs, opts)
  end

  @doc """
  Updates the pc_user password.

  Returns a tuple with the updated pc_user, as well as a list of expired tokens.

  ## Examples

      iex> update_pc_user_password(pc_user, %{password: ...})
      {:ok, {%PCUser{}, [...]}}

      iex> update_pc_user_password(pc_user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_pc_user_password(pc_user, attrs) do
    pc_user
    |> PCUser.password_changeset(attrs)
    |> update_pc_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_pc_user_session_token(pc_user) do
    {token, pc_user_token} = PCUserToken.build_session_token(pc_user)
    Repo.insert!(pc_user_token)
    token
  end

  @doc """
  Gets the pc_user with the given signed token.

  If the token is valid `{pc_user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_pc_user_by_session_token(token) do
    {:ok, query} = PCUserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the pc_user with the given magic link token.
  """
  def get_pc_user_by_magic_link_token(token) do
    with {:ok, query} <- PCUserToken.verify_magic_link_token_query(token),
         {pc_user, _token} <- Repo.one(query) do
      pc_user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the pc_user in by magic link.

  There are three cases to consider:

  1. The pc_user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The pc_user has not confirmed their email and no password is set.
     In this case, the pc_user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The pc_user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_pc_user_by_magic_link(token) do
    {:ok, query} = PCUserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%PCUser{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%PCUser{confirmed_at: nil} = pc_user, _token} ->
        pc_user
        |> PCUser.confirm_changeset()
        |> update_pc_user_and_delete_all_tokens()

      {pc_user, token} ->
        Repo.delete!(token)
        {:ok, {pc_user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given pc_user.

  ## Examples

      iex> deliver_pc_user_update_email_instructions(pc_user, current_email, &url(~p"/pc_users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_pc_user_update_email_instructions(
        %PCUser{} = pc_user,
        current_email,
        update_email_url_fun
      )
      when is_function(update_email_url_fun, 1) do
    {encoded_token, pc_user_token} =
      PCUserToken.build_email_token(pc_user, "change:#{current_email}")

    Repo.insert!(pc_user_token)

    PCUserNotifier.deliver_update_email_instructions(
      pc_user,
      update_email_url_fun.(encoded_token)
    )
  end

  @doc """
  Delivers the magic link login instructions to the given pc_user.
  """
  def deliver_login_instructions(%PCUser{} = pc_user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, pc_user_token} = PCUserToken.build_email_token(pc_user, "login")
    Repo.insert!(pc_user_token)
    PCUserNotifier.deliver_login_instructions(pc_user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_pc_user_session_token(token) do
    Repo.delete_all(from(PCUserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## TOTP (RFC 6238) — second factor enforced after password / magic link

  @doc """
  Generates a fresh 20-byte TOTP secret for the user, persists it, and clears any
  prior `totp_confirmed_at`. Re-running this rotates the secret and forces the
  user to re-confirm. Idempotent within an unconfirmed enrollment: if the user
  already has an unconfirmed `totp_secret`, it is returned unchanged so a
  reloaded setup page shows the same QR code.
  """
  def setup_totp(%PCUser{totp_secret: secret, totp_confirmed_at: nil} = pc_user)
      when is_binary(secret),
      do: {:ok, pc_user}

  def setup_totp(%PCUser{} = pc_user) do
    pc_user
    |> Ecto.Changeset.change(%{totp_secret: NimbleTOTP.secret(), totp_confirmed_at: nil})
    |> Repo.update()
  end

  @doc """
  Verifies the first OTP after enrollment. On success, marks the secret as
  confirmed by setting `totp_confirmed_at`. The OTP is checked against ±30s
  drift via `NimbleTOTP.valid?/3`.
  """
  def confirm_totp(%PCUser{totp_secret: secret} = pc_user, otp)
      when is_binary(secret) and is_binary(otp) do
    if NimbleTOTP.valid?(secret, otp) do
      pc_user
      |> Ecto.Changeset.change(%{totp_confirmed_at: DateTime.utc_now(:second)})
      |> Repo.update()
    else
      {:error, :invalid_otp}
    end
  end

  def confirm_totp(_pc_user, _otp), do: {:error, :no_secret}

  @doc """
  Verifies an OTP against an already-confirmed user's secret. Returns boolean.
  Always returns false if the user has no confirmed secret — callers must not
  rely on this as a "create on first verify" path.
  """
  def verify_totp(%PCUser{totp_secret: secret, totp_confirmed_at: %DateTime{}}, otp)
      when is_binary(secret) and is_binary(otp) do
    NimbleTOTP.valid?(secret, otp)
  end

  def verify_totp(_pc_user, _otp), do: false

  @doc """
  Returns the otpauth:// URI for the user's current secret, suitable for QR
  encoding. Issuer is "Evenglass" so authenticator apps group entries.
  """
  def totp_uri(%PCUser{email: email, totp_secret: secret}) when is_binary(secret) do
    NimbleTOTP.otpauth_uri("Evenglass:#{email}", secret, issuer: "Evenglass")
  end

  @doc """
  Returns the user's TOTP secret base32-encoded — what users type into apps that
  cannot scan QR codes. Returns nil when no secret is set.
  """
  def totp_base32(%PCUser{totp_secret: secret}) when is_binary(secret) do
    Base.encode32(secret, padding: false)
  end

  def totp_base32(_), do: nil

  ## Token helper

  defp update_pc_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, pc_user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(PCUserToken, pc_user_id: pc_user.id)

        Repo.delete_all(
          from(t in PCUserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id))
        )

        {:ok, {pc_user, tokens_to_expire}}
      end
    end)
  end
end
