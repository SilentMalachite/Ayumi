defmodule Ayumi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AyumiWeb.Telemetry,
      Ayumi.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:ayumi, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:ayumi, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Ayumi.PubSub},
      AyumiWeb.Presence,
      # Start a worker by calling: Ayumi.Worker.start_link(arg)
      # {Ayumi.Worker, arg},
      # Start to serve requests, typically the last entry
      AyumiWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ayumi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AyumiWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
