defmodule Evenglass.Release do
  @moduledoc """
  Tasks invoked from `bin/evenglass eval` inside a mix release container,
  since Mix tasks are not available at runtime.

  Usage:
      docker compose exec app /app/bin/evenglass eval "Evenglass.Release.migrate()"
      docker compose exec app /app/bin/evenglass eval \\
        'Evenglass.Release.create_pc_admin("you@example.com", "initial-password-12chars")'
  """

  @app :evenglass

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Bootstraps a PC admin account with a known email + initial password. The
  account is marked `confirmed_at` immediately (no email-verification round-trip
  needed). On first login the admin will be forced through the TOTP enrollment
  page; only after that completes do they get full session access to /admin.

  Idempotent: if a user with the given email already exists, returns `:already_exists`
  rather than overwriting the password.

  Run inside the release container, e.g.:

      docker compose exec app /app/bin/evenglass eval \\
        'Evenglass.Release.create_pc_admin("admin@example.com", "change-me-on-first-login")'

  The password must be at least 12 characters (matches PCUser.password_changeset).
  Rotate it from /pc_users/settings after first login.
  """
  def create_pc_admin(email, password) when is_binary(email) and is_binary(password) do
    load_app()

    # Start only the Repo — not the full Endpoint — since `eval` runs in a fresh
    # BEAM alongside the live release; starting Endpoint would clash on :4000.
    {:ok, _, _} =
      Ecto.Migrator.with_repo(Evenglass.Repo, fn _repo ->
        case Evenglass.Accounts.get_pc_user_by_email(email) do
          %Evenglass.Accounts.PCUser{} ->
            IO.puts(:stderr, "PC admin '#{email}' already exists; skipping.")
            :already_exists

          nil ->
            # Build the account with both email + password set, and stamp
            # confirmed_at so the user can log in directly without going through
            # the magic-link confirmation step.
            changeset =
              %Evenglass.Accounts.PCUser{}
              |> Evenglass.Accounts.PCUser.email_changeset(%{email: email})
              |> Evenglass.Accounts.PCUser.password_changeset(%{password: password},
                hash_password: true
              )
              |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))

            case Evenglass.Repo.insert(changeset) do
              {:ok, pc_user} ->
                IO.puts("Created PC admin '#{pc_user.email}' (id: #{pc_user.id}).")
                IO.puts("Visit /pc_users/log-in; on first login you'll set up TOTP.")
                {:ok, pc_user}

              {:error, changeset} ->
                IO.puts(:stderr, "Failed to create PC admin: #{inspect(changeset.errors)}")
                {:error, changeset}
            end
        end
      end)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
