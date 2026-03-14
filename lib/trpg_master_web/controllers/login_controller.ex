defmodule TrpgMasterWeb.LoginController do
  use TrpgMasterWeb, :controller

  def show(conn, _params) do
    render(conn, :show, error: nil)
  end

  def login(conn, %{"password" => password}) do
    expected = Application.get_env(:trpg_master, :auth_password)

    if is_nil(expected) || expected == "" || password == expected do
      conn
      |> put_session(:authenticated, true)
      |> redirect(to: ~p"/")
    else
      render(conn, :show, error: "비밀번호가 틀렸습니다.")
    end
  end

  def logout(conn, _params) do
    conn
    |> delete_session(:authenticated)
    |> redirect(to: ~p"/login")
  end
end
