defmodule EvenglassWeb.Router do
  use EvenglassWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EvenglassWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated_api do
    plug :accepts, ["json"]
    plug EvenglassWeb.Plugs.AuthenticatedAPI
  end

  scope "/", EvenglassWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/admin", EvenglassWeb do
    pipe_through :browser

    live_session :admin do
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

    # PC commands — currently unprotected; task 1.5 introduces PC user auth
    # and an :authenticated_admin_api pipeline that will guard this endpoint.
    scope "/" do
      pipe_through :api
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
end
