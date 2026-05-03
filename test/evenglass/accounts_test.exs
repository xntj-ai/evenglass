defmodule Evenglass.AccountsTest do
  use Evenglass.DataCase

  alias Evenglass.Accounts

  import Evenglass.AccountsFixtures
  alias Evenglass.Accounts.{PCUser, PCUserToken}

  describe "get_pc_user_by_email/1" do
    test "does not return the pc_user if the email does not exist" do
      refute Accounts.get_pc_user_by_email("unknown@example.com")
    end

    test "returns the pc_user if the email exists" do
      %{id: id} = pc_user = pc_user_fixture()
      assert %PCUser{id: ^id} = Accounts.get_pc_user_by_email(pc_user.email)
    end

    test "matches case-insensitively (lookup normalizes input email)" do
      %{id: id} = pc_user = pc_user_fixture()
      assert %PCUser{id: ^id} = Accounts.get_pc_user_by_email(String.upcase(pc_user.email))
    end
  end

  describe "get_pc_user_by_email_and_password/2" do
    test "does not return the pc_user if the email does not exist" do
      refute Accounts.get_pc_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the pc_user if the password is not valid" do
      pc_user = pc_user_fixture() |> set_password()
      refute Accounts.get_pc_user_by_email_and_password(pc_user.email, "invalid")
    end

    test "returns the pc_user if the email and password are valid" do
      %{id: id} = pc_user = pc_user_fixture() |> set_password()

      assert %PCUser{id: ^id} =
               Accounts.get_pc_user_by_email_and_password(pc_user.email, valid_pc_user_password())
    end

    test "matches case-insensitively on email" do
      %{id: id} = pc_user = pc_user_fixture() |> set_password()

      assert %PCUser{id: ^id} =
               Accounts.get_pc_user_by_email_and_password(
                 String.upcase(pc_user.email),
                 valid_pc_user_password()
               )
    end
  end

  describe "get_pc_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_pc_user!("11111111-1111-1111-1111-111111111111")
      end
    end

    test "returns the pc_user with the given id" do
      %{id: id} = pc_user = pc_user_fixture()
      assert %PCUser{id: ^id} = Accounts.get_pc_user!(pc_user.id)
    end
  end

  describe "register_pc_user/1" do
    test "requires email to be set" do
      {:error, changeset} = Accounts.register_pc_user(%{})

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email when given" do
      {:error, changeset} = Accounts.register_pc_user(%{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "stores email lowercased + trimmed" do
      attrs = %{email: "  Mixed.Case@Example.COM  "}
      {:ok, pc_user} = Accounts.register_pc_user(attrs)
      assert pc_user.email == "mixed.case@example.com"
    end

    test "validates maximum values for email for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_pc_user(%{email: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness" do
      %{email: email} = pc_user_fixture()
      {:error, changeset} = Accounts.register_pc_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the uppercased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.register_pc_user(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers pc_users without password" do
      email = unique_pc_user_email()
      {:ok, pc_user} = Accounts.register_pc_user(valid_pc_user_attributes(email: email))
      assert pc_user.email == email
      assert is_nil(pc_user.hashed_password)
      assert is_nil(pc_user.confirmed_at)
      assert is_nil(pc_user.password)
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%PCUser{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%PCUser{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%PCUser{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %PCUser{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%PCUser{})
    end
  end

  describe "change_pc_user_email/3" do
    test "returns a pc_user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_pc_user_email(%PCUser{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_pc_user_update_email_instructions/3" do
    setup do
      %{pc_user: pc_user_fixture()}
    end

    test "sends token through notification", %{pc_user: pc_user} do
      token =
        extract_pc_user_token(fn url ->
          Accounts.deliver_pc_user_update_email_instructions(pc_user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert pc_user_token = Repo.get_by(PCUserToken, token: :crypto.hash(:sha256, token))
      assert pc_user_token.pc_user_id == pc_user.id
      assert pc_user_token.sent_to == pc_user.email
      assert pc_user_token.context == "change:current@example.com"
    end
  end

  describe "update_pc_user_email/2" do
    setup do
      pc_user = unconfirmed_pc_user_fixture()
      email = unique_pc_user_email()

      token =
        extract_pc_user_token(fn url ->
          Accounts.deliver_pc_user_update_email_instructions(
            %{pc_user | email: email},
            pc_user.email,
            url
          )
        end)

      %{pc_user: pc_user, token: token, email: email}
    end

    test "updates the email with a valid token", %{pc_user: pc_user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Accounts.update_pc_user_email(pc_user, token)
      changed_pc_user = Repo.get!(PCUser, pc_user.id)
      assert changed_pc_user.email != pc_user.email
      assert changed_pc_user.email == email
      refute Repo.get_by(PCUserToken, pc_user_id: pc_user.id)
    end

    test "does not update email with invalid token", %{pc_user: pc_user} do
      assert Accounts.update_pc_user_email(pc_user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(PCUser, pc_user.id).email == pc_user.email
      assert Repo.get_by(PCUserToken, pc_user_id: pc_user.id)
    end

    test "does not update email if pc_user email changed", %{pc_user: pc_user, token: token} do
      assert Accounts.update_pc_user_email(%{pc_user | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(PCUser, pc_user.id).email == pc_user.email
      assert Repo.get_by(PCUserToken, pc_user_id: pc_user.id)
    end

    test "does not update email if token expired", %{pc_user: pc_user, token: token} do
      {1, nil} = Repo.update_all(PCUserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_pc_user_email(pc_user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(PCUser, pc_user.id).email == pc_user.email
      assert Repo.get_by(PCUserToken, pc_user_id: pc_user.id)
    end
  end

  describe "change_pc_user_password/3" do
    test "returns a pc_user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_pc_user_password(%PCUser{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_pc_user_password(
          %PCUser{},
          %{
            "password" => "new valid password"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_pc_user_password/2" do
    setup do
      %{pc_user: pc_user_fixture()}
    end

    test "validates password", %{pc_user: pc_user} do
      {:error, changeset} =
        Accounts.update_pc_user_password(pc_user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{pc_user: pc_user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_pc_user_password(pc_user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{pc_user: pc_user} do
      {:ok, {pc_user, expired_tokens}} =
        Accounts.update_pc_user_password(pc_user, %{
          password: "new valid password"
        })

      assert expired_tokens == []
      assert is_nil(pc_user.password)
      assert Accounts.get_pc_user_by_email_and_password(pc_user.email, "new valid password")
    end

    test "deletes all tokens for the given pc_user", %{pc_user: pc_user} do
      _ = Accounts.generate_pc_user_session_token(pc_user)

      {:ok, {_, _}} =
        Accounts.update_pc_user_password(pc_user, %{
          password: "new valid password"
        })

      refute Repo.get_by(PCUserToken, pc_user_id: pc_user.id)
    end
  end

  describe "generate_pc_user_session_token/1" do
    setup do
      %{pc_user: pc_user_fixture()}
    end

    test "generates a token", %{pc_user: pc_user} do
      token = Accounts.generate_pc_user_session_token(pc_user)
      assert pc_user_token = Repo.get_by(PCUserToken, token: token)
      assert pc_user_token.context == "session"
      assert pc_user_token.authenticated_at != nil

      # Creating the same token for another pc_user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%PCUserToken{
          token: pc_user_token.token,
          pc_user_id: pc_user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given pc_user in new token", %{pc_user: pc_user} do
      pc_user = %{pc_user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_pc_user_session_token(pc_user)
      assert pc_user_token = Repo.get_by(PCUserToken, token: token)
      assert pc_user_token.authenticated_at == pc_user.authenticated_at
      assert DateTime.compare(pc_user_token.inserted_at, pc_user.authenticated_at) == :gt
    end
  end

  describe "get_pc_user_by_session_token/1" do
    setup do
      pc_user = pc_user_fixture()
      token = Accounts.generate_pc_user_session_token(pc_user)
      %{pc_user: pc_user, token: token}
    end

    test "returns pc_user by token", %{pc_user: pc_user, token: token} do
      assert {session_pc_user, token_inserted_at} = Accounts.get_pc_user_by_session_token(token)
      assert session_pc_user.id == pc_user.id
      assert session_pc_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return pc_user for invalid token" do
      refute Accounts.get_pc_user_by_session_token("oops")
    end

    test "does not return pc_user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(PCUserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_pc_user_by_session_token(token)
    end
  end

  describe "get_pc_user_by_magic_link_token/1" do
    setup do
      pc_user = pc_user_fixture()
      {encoded_token, _hashed_token} = generate_pc_user_magic_link_token(pc_user)
      %{pc_user: pc_user, token: encoded_token}
    end

    test "returns pc_user by token", %{pc_user: pc_user, token: token} do
      assert session_pc_user = Accounts.get_pc_user_by_magic_link_token(token)
      assert session_pc_user.id == pc_user.id
    end

    test "does not return pc_user for invalid token" do
      refute Accounts.get_pc_user_by_magic_link_token("oops")
    end

    test "does not return pc_user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(PCUserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_pc_user_by_magic_link_token(token)
    end
  end

  describe "login_pc_user_by_magic_link/1" do
    test "confirms pc_user and expires tokens" do
      pc_user = unconfirmed_pc_user_fixture()
      refute pc_user.confirmed_at
      {encoded_token, hashed_token} = generate_pc_user_magic_link_token(pc_user)

      assert {:ok, {pc_user, [%{token: ^hashed_token}]}} =
               Accounts.login_pc_user_by_magic_link(encoded_token)

      assert pc_user.confirmed_at
    end

    test "returns pc_user and (deleted) token for confirmed pc_user" do
      pc_user = pc_user_fixture()
      assert pc_user.confirmed_at
      {encoded_token, _hashed_token} = generate_pc_user_magic_link_token(pc_user)
      assert {:ok, {^pc_user, []}} = Accounts.login_pc_user_by_magic_link(encoded_token)
      # one time use only
      assert {:error, :not_found} = Accounts.login_pc_user_by_magic_link(encoded_token)
    end

    test "raises when unconfirmed pc_user has password set" do
      pc_user = unconfirmed_pc_user_fixture()
      {1, nil} = Repo.update_all(PCUser, set: [hashed_password: "hashed"])
      {encoded_token, _hashed_token} = generate_pc_user_magic_link_token(pc_user)

      assert_raise RuntimeError, ~r/magic link log in is not allowed/, fn ->
        Accounts.login_pc_user_by_magic_link(encoded_token)
      end
    end
  end

  describe "delete_pc_user_session_token/1" do
    test "deletes the token" do
      pc_user = pc_user_fixture()
      token = Accounts.generate_pc_user_session_token(pc_user)
      assert Accounts.delete_pc_user_session_token(token) == :ok
      refute Accounts.get_pc_user_by_session_token(token)
    end
  end

  describe "deliver_login_instructions/2" do
    setup do
      %{pc_user: unconfirmed_pc_user_fixture()}
    end

    test "sends token through notification", %{pc_user: pc_user} do
      token =
        extract_pc_user_token(fn url ->
          Accounts.deliver_login_instructions(pc_user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert pc_user_token = Repo.get_by(PCUserToken, token: :crypto.hash(:sha256, token))
      assert pc_user_token.pc_user_id == pc_user.id
      assert pc_user_token.sent_to == pc_user.email
      assert pc_user_token.context == "login"
    end
  end

  describe "inspect/2 for the PCUser module" do
    test "does not include password" do
      refute inspect(%PCUser{password: "123456"}) =~ "password: \"123456\""
    end
  end
end
