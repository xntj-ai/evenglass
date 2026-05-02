defmodule EvenglassWeb.Router do
  use EvenglassWeb, :router

  import EvenglassWeb.PCUserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EvenglassWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_pc_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated_api do
    plug :accepts, ["json"]
    plug EvenglassWeb.Plugs.AuthenticatedAPI
  end

  # Browser-session-authenticated API. Required for endpoints that PCs (or the
  # admin browser) hit with the same `:pc_user_token` cookie used for /admin.
  # Failures emit JSON 401, never an HTML redirect.
  pipeline :authenticated_admin_api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :fetch_current_scope_for_pc_user
    plug :require_pc_admin_api
  end

  scope "/", EvenglassWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/admin", EvenglassWeb do
    pipe_through [:browser, :require_pc_admin]

    live_session :admin, on_mount: [{EvenglassWeb.PCUserAuth, :require_pc_admin}] do
      live "/events", Admin.EventsLive
      live "/devices", Admin.DevicesLive
    end
  end

  scope "/api/g2", EvenglassWeb do
    # Public auth endpoint — no token required
    scope "/" do
      pipe_through :api
      post "/enroll", Api.AuthController, :enroll
    end

    # Authenticated Hub App endpoints — device_token Bearer required
    scope "/" do
      pipe_through :authenticated_api
      post "/refresh", Api.AuthController, :refresh
      get "/whoami", Api.AuthController, :whoami
      post "/socket-token", Api.AuthController, :socket_token
      post "/events", G2Controller, :create_event
    end

    # PC commands — gated on a 2FA-completed admin session.
    scope "/" do
      pipe_through :authenticated_admin_api
      post "/commands", G2Controller, :create_command
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:evenglass, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EvenglassWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", EvenglassWeb do
    pipe_through [:browser, :require_authenticated_pc_user]

    live_session :require_authenticated_pc_user,
      on_mount: [{EvenglassWeb.PCUserAuth, :require_authenticated}] do
      live "/pc_users/settings", PCUserLive.Settings, :edit
      live "/pc_users/settings/confirm-email/:token", PCUserLive.Settings, :confirm_email
    end

    post "/pc_users/update-password", PCUserSessionController, :update_password
  end

  scope "/", EvenglassWeb do
    pipe_through [:browser]

    live_session :current_pc_user,
      on_mount: [{EvenglassWeb.PCUserAuth, :mount_current_scope}] do
      # PC admins are bootstrapped via Evenglass.Release.create_pc_admin/2;
      # public self-registration is intentionally disabled.
      live "/pc_users/log-in", PCUserLive.Login, :new
      live "/pc_users/log-in/:token", PCUserLive.Confirmation, :new
    end

    post "/pc_users/log-in", PCUserSessionController, :create
    delete "/pc_users/log-out", PCUserSessionController, :delete

    # TOTP second-factor pages — accessible only when the session carries a
    # valid `pc_user_pending_2fa_id` marker (enforced by `:require_pending_2fa`
    # on_mount for LiveViews; controller actions check via fetch_pending_two_factor).
    live_session :pending_2fa,
      on_mount: [{EvenglassWeb.PCUserAuth, :require_pending_2fa}] do
      live "/pc_users/totp/setup", PCUserLive.TotpSetup
      live "/pc_users/totp/verify", PCUserLive.TotpVerify
    end

    post "/pc_users/totp/setup", PCUserSessionController, :setup_totp
    post "/pc_users/totp/verify", PCUserSessionController, :verify_totp
  end
end
