defmodule TrpgMaster.MixProject do
  use Mix.Project

  def project do
    [
      app: :trpg_master,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {TrpgMaster.Application, []},
      extra_applications: [:logger, :runtime_tools, :ssl, :inets]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core Phoenix
      {:phoenix, github: "phoenixframework/phoenix", tag: "v1.7.21", override: true},
      {:phoenix_html, github: "phoenixframework/phoenix_html", tag: "v4.2.1", override: true},
      {:phoenix_live_view, github: "phoenixframework/phoenix_live_view", tag: "v0.20.17", override: true},
      {:phoenix_live_reload, github: "phoenixframework/phoenix_live_reload", tag: "v1.5.3", only: :dev, override: true},
      {:jason, github: "michalmuskala/jason", tag: "v1.4.4", override: true},
      {:bandit, github: "mtrudel/bandit", tag: "1.6.10", override: true},
      {:gettext, github: "elixir-gettext/gettext", tag: "v0.26.2", override: true},
      {:dns_cluster, github: "phoenixframework/dns_cluster", tag: "v0.1.3", override: true},
      {:telemetry_metrics, github: "beam-telemetry/telemetry_metrics", tag: "v1.1.0", override: true},
      {:telemetry_poller, github: "beam-telemetry/telemetry_poller", tag: "v1.1.0", override: true},

      # Transitive deps
      {:plug, github: "elixir-plug/plug", tag: "v1.19.1", override: true},
      {:plug_crypto, github: "elixir-plug/plug_crypto", tag: "v2.1.1", override: true},
      {:telemetry, github: "beam-telemetry/telemetry", tag: "v1.3.0", override: true},
      {:phoenix_pubsub, github: "phoenixframework/phoenix_pubsub", tag: "v2.1.3", override: true},
      {:phoenix_template, github: "phoenixframework/phoenix_template", tag: "v1.0.4", override: true},
      {:websock_adapter, github: "phoenixframework/websock_adapter", tag: "0.5.8", override: true},
      {:castore, path: "local_deps/castore", override: true},
      {:websock, github: "phoenixframework/websock", tag: "0.5.3", override: true},
      {:thousand_island, github: "mtrudel/thousand_island", tag: "1.4.3", override: true},
      {:hpax, github: "elixir-mint/hpax", tag: "v1.0.3", override: true},
      {:mime, github: "elixir-plug/mime", tag: "v2.0.7", override: true},
      {:expo, github: "elixir-gettext/expo", tag: "v1.1.1", override: true},
      {:file_system, github: "falood/file_system", tag: "v1.1.1", override: true},

      # Markdown
      {:earmark, github: "pragdave/earmark", tag: "v1.4.9", override: true}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
