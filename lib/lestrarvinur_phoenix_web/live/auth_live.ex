defmodule LestrarvinurPhoenixWeb.AuthLive do
  use LestrarvinurPhoenixWeb, :live_view

  alias LestrarvinurPhoenix.Accounts

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:username, "")
     |> assign(:password, "")
     |> assign(:password_confirmation, "")
     |> assign(:is_login, true)
     |> assign(:error, nil)}
  end

  def handle_event("toggle_mode", _params, socket) do
    {:noreply,
     socket
     |> assign(:is_login, !socket.assigns.is_login)
     |> assign(:error, nil)}
  end

  def handle_event("validate", params, socket) do
    {:noreply,
     socket
     |> assign(:username, Map.get(params, "username", ""))
     |> assign(:password, Map.get(params, "password", ""))
     |> assign(:password_confirmation, Map.get(params, "password_confirmation", ""))}
  end

  def handle_event("submit", params, socket) do
    username = String.trim(Map.get(params, "username", ""))
    password = Map.get(params, "password", "")
    password_confirmation = Map.get(params, "password_confirmation", "")

    cond do
      username == "" ->
        {:noreply, assign(socket, :error, "Notandanafn má ekki vera tómt")}

      password == "" ->
        {:noreply, assign(socket, :error, "Lykilorð má ekki vera tómt")}

      true ->
        if socket.assigns.is_login do
          handle_login(socket, username, password)
        else
          handle_registration(socket, username, password, password_confirmation)
        end
    end
  end

  # Not intended for use outside this module
  defp handle_login(socket, username, password) do
    case Accounts.authenticate_user(username, password) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Velkomin/n!")
         |> redirect(to: ~p"/dashboard?username=#{user.username}")}

      {:error, :invalid_credentials} ->
        {:noreply, assign(socket, :error, "Rangt notandanafn eða lykilorð")}
    end
  end

  # Not intended for use outside this module
  defp handle_registration(socket, username, password, password_confirmation) do
    attrs = %{
      username: username,
      password: password,
      password_confirmation: password_confirmation
    }

    case Accounts.create_user(attrs) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Aðgangur stofnaður!")
         |> redirect(to: ~p"/dashboard?username=#{user.username}")}

      {:error, changeset} ->
        error_message =
          case changeset.errors do
            [{:username, {msg, _}} | _] -> msg
            [{:password, {msg, _}} | _] -> msg
            [{:password_confirmation, {msg, _}} | _] -> msg
            _ -> "Villa kom upp við skráningu"
          end

        {:noreply, assign(socket, :error, error_message)}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center min-h-screen bg-sky-50 p-4">
      <div class="bg-white p-8 rounded-3xl shadow-xl w-full max-w-md border-4 border-sky-200">
        <h1 class="text-4xl font-extrabold text-sky-600 mb-2 text-center">Lestrarvinur 📚</h1>
        <p class="text-center text-slate-500 mb-8">Lærðu að lesa!</p>

        <form phx-submit="submit" phx-change="validate" class="space-y-6">
          <div>
            <label class="block text-sm font-medium text-slate-700 mb-1">Notandanafn</label>
            <input
              type="text"
              name="username"
              required
              class="w-full px-4 py-3 rounded-xl border-2 border-slate-200 focus:border-sky-400 focus:outline-none text-lg"
              placeholder="Sláðu inn notandanafn"
              value={@username}
              phx-debounce="300"
            />
          </div>

          <div>
            <label class="block text-sm font-medium text-slate-700 mb-1">Lykilorð</label>
            <input
              type="password"
              name="password"
              required
              class="w-full px-4 py-3 rounded-xl border-2 border-slate-200 focus:border-sky-400 focus:outline-none text-lg"
              placeholder="Sláðu inn lykilorð"
              value={@password}
              phx-debounce="300"
            />
          </div>

          <%= if !@is_login do %>
            <div>
              <label class="block text-sm font-medium text-slate-700 mb-1">
                Staðfesta lykilorð
              </label>
              <input
                type="password"
                name="password_confirmation"
                required
                class="w-full px-4 py-3 rounded-xl border-2 border-slate-200 focus:border-sky-400 focus:outline-none text-lg"
                placeholder="Sláðu inn lykilorð aftur"
                value={@password_confirmation}
                phx-debounce="300"
              />
            </div>
          <% end %>

          <%= if @error do %>
            <div class="bg-red-50 border-2 border-red-200 text-red-700 px-4 py-3 rounded-xl text-sm">
              {@error}
            </div>
          <% end %>

          <button
            type="submit"
            class="w-full bg-sky-500 hover:bg-sky-600 text-white font-bold py-4 rounded-xl text-xl shadow-lg transform transition active:scale-95"
          >
            {if @is_login, do: "Skrá inn", else: "Nýskráning"}
          </button>
        </form>

        <div class="mt-6 text-center">
          <button
            phx-click="toggle_mode"
            class="text-sky-500 hover:text-sky-700 font-medium"
          >
            {if @is_login,
              do: "Búa til nýjan aðgang?",
              else: "Áttu nú þegar aðgang?"}
          </button>
        </div>
      </div>
    </div>
    """
  end
end
