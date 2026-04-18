defmodule TrpgMasterWeb.CharacterCreateLiveTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket
  alias TrpgMasterWeb.CharacterCreateLive

  test "set_alignment handles direct input change payloads" do
    socket = %Socket{assigns: %{__changed__: %{}, alignment: "중립"}}

    assert {:noreply, updated_socket} =
             CharacterCreateLive.handle_event(
               "set_alignment",
               %{"value" => "혼돈 선"},
               socket
             )

    assert updated_socket.assigns.alignment == "혼돈 선"
  end

  test "set_alignment handles form change payloads" do
    socket = %Socket{assigns: %{__changed__: %{}, alignment: "중립"}}

    assert {:noreply, updated_socket} =
             CharacterCreateLive.handle_event(
               "set_alignment",
               %{"alignment" => "질서 선"},
               socket
             )

    assert updated_socket.assigns.alignment == "질서 선"
  end
end
