defmodule CAStore do
  @moduledoc "Stub CAStore providing CA certificate bundle path."

  @spec file_path() :: Path.t()
  def file_path do
    Application.app_dir(:castore, "priv/cacerts.pem")
  end
end
