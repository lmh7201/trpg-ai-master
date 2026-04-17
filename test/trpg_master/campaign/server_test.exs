defmodule TrpgMaster.Campaign.ServerTest do
  use ExUnit.Case, async: false

  alias TrpgMaster.Campaign.{Server, State}

  setup do
    original_data_dir = Application.get_env(:trpg_master, :data_dir)

    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "trpg_master_server_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf(tmp_dir)
    File.mkdir_p!(tmp_dir)
    Application.put_env(:trpg_master, :data_dir, tmp_dir)

    on_exit(fn ->
      restore_data_dir(original_data_dir)
      File.rm_rf(tmp_dir)
    end)

    :ok
  end

  test "set_character/2 updates campaign state through the public server API" do
    campaign_id = "campaign-#{System.unique_integer([:positive])}"
    initial_state = %State{id: campaign_id, name: "Refactor Test"}
    character = %{"name" => "아리아", "level" => 1, "class" => "위자드"}

    start_supervised!({Server, initial_state})

    assert :ok = Server.set_character(campaign_id, character)

    assert %State{characters: [saved_character]} = Server.get_state(campaign_id)
    assert saved_character == character
  end

  defp restore_data_dir(nil), do: Application.delete_env(:trpg_master, :data_dir)
  defp restore_data_dir(path), do: Application.put_env(:trpg_master, :data_dir, path)
end
