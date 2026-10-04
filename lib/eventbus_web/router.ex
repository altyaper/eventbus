defmodule EventbusWeb.Router do
  use EventbusWeb, :router

  import EventbusWeb.UserAuth, only: [fetch_current_scope: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EventbusWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug EventbusWeb.Plugs.RequireAppCredentials
  end

  scope "/", EventbusWeb do
    pipe_through :browser

    live_session :setup, on_mount: [{EventbusWeb.UserAuth, :redirect_if_set_up}] do
      live "/setup", SetupLive
    end

    live_session :login,
      on_mount: [
        {EventbusWeb.UserAuth, :require_setup},
        {EventbusWeb.UserAuth, :redirect_if_authenticated}
      ] do
      live "/login", LoginLive
    end

    live_session :public, on_mount: [{EventbusWeb.UserAuth, :mount_current_scope}] do
      live "/docs", DocsLive
    end

    get "/", HomeController, :index
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete

    live_session :authenticated,
      on_mount: [
        {EventbusWeb.UserAuth, :require_setup},
        {EventbusWeb.UserAuth, :require_authenticated}
      ] do
      live "/apps", AppsLive
      live "/apps/:slug", AppLive, :index
      live "/apps/:slug/topics", AppLive, :topics
      live "/apps/:slug/credentials", AppLive, :credentials
      live "/apps/:slug/origins", AppLive, :origins
      live "/apps/:slug/settings", AppLive, :settings
      live "/apps/:slug/chat", AppLive, :chat
      live "/apps/:slug/topics/:name", TopicShowLive
      live "/apps/:slug/chat/rooms/:id", ChatRoomLive
      live "/apps/:slug/chat/demo", ChatDemoLive
    end
  end

  scope "/api", EventbusWeb do
    pipe_through :api

    post "/topics/:name/events", TopicEventController, :create

    post "/tokens", TopicTokenController, :create
    post "/tokens/revoke", TopicTokenController, :revoke

    post "/chat/tokens", ChatTokenController, :create
    post "/chat/rooms", ChatRoomController, :create
    post "/chat/rooms/:room_id/members", ChatRoomController, :add_member
    delete "/chat/rooms/:room_id/members/:user_id", ChatRoomController, :remove_member
    post "/chat/rooms/:room_id/messages", ChatRoomController, :create_message
    delete "/chat/rooms/:room_id/messages/:id", ChatRoomController, :delete_message
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:eventbus, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EventbusWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
