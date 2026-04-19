defmodule TrpgMasterWeb.CharacterCreateSessionTest do
  use ExUnit.Case, async: true

  alias TrpgMasterWeb.CharacterCreateSession

  test "mount_assigns/2 redirects to play when there is no character data" do
    assert {:navigate, "/play/campaign-1"} =
             CharacterCreateSession.mount_assigns("campaign-1",
               classes: [],
               server_alive?: fn _id -> true end
             )
  end

  test "mount_assigns/2 starts the campaign when the server is missing" do
    Process.put(:started_campaigns, [])

    on_exit(fn ->
      Process.delete(:started_campaigns)
    end)

    assert {:ok, assigns} =
             CharacterCreateSession.mount_assigns("campaign-2",
               classes: [%{"id" => "wizard"}],
               races: [%{"id" => "elf"}],
               backgrounds: [%{"id" => "sage"}],
               server_alive?: fn _id -> false end,
               start_campaign: fn campaign_id ->
                 Process.put(
                   :started_campaigns,
                   Process.get(:started_campaigns, []) ++ [campaign_id]
                 )

                 {:ok, self()}
               end
             )

    assert assigns.campaign_id == "campaign-2"
    assert Process.get(:started_campaigns) == ["campaign-2"]
  end

  test "finish/2 persists the character and returns the campaign id" do
    Process.put(:saved_character, nil)

    on_exit(fn ->
      Process.delete(:saved_character)
    end)

    assigns = %{campaign_id: "campaign-3"}
    character = %{"name" => "엘라라"}

    assert {:ok, "campaign-3"} =
             CharacterCreateSession.finish(assigns,
               finish_flow: fn _assigns -> {:ok, character} end,
               set_character: fn campaign_id, saved_character ->
                 Process.put(:saved_character, {campaign_id, saved_character})
                 :ok
               end
             )

    assert Process.get(:saved_character) == {"campaign-3", character}
  end

  test "select_class/2 delegates lookup before applying flow updates" do
    wizard = %{"id" => "wizard", "name" => %{"ko" => "위자드"}}

    updates =
      CharacterCreateSession.select_class("wizard",
        get_class: fn "wizard" -> wizard end
      )

    assert updates.selected_class == wizard
    assert updates.detail_panel == nil
    assert updates.is_spellcaster == true
  end
end
