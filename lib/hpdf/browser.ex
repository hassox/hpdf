defmodule HPDF.Browser do
  @moduledoc false

  # Manages browser sessions. This manages creating and cleaning up browser sessions as contexts in chrome.
  # Each session is provided with a new 'Context' - similar to an Incognito window.
  #
  # This module manages the browser and utilizes the master web socket to create and shutdown contexts.
  # Each time we print a page, we create a new context.
  # The browser will monitor the requesting process so that once it stops, the context is removed automatically

  use HPDF.WebSocket
  require Logger

  @initial_state %{
    connected?: false,
    debugger_http_address: nil,
    socket_uri: nil,
    session_counter: 1,
    sessions: %{},
    socket: nil,
    receiver: nil,
  }

  def start_link(), do: start_link([])
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    config = Application.get_env(:hpdf, HPDF, [])

    debugger_address = Keyword.get(config, :address, "http://localhost:9222")

    # TODO: fail if we don't get a socket address
    socket_address = fetch_controller_socket_address(debugger_address)
    ws_uri = URI.parse(socket_address)

    {:ok, init_state} = super(socket_args: [{ws_uri.host, ws_uri.port}, [path: ws_uri.path]])

    state =
      %{@initial_state | debugger_http_address: debugger_address,
                         socket_uri: ws_uri,
                         receiver: init_state.receiver,
                         socket: init_state.socket}


    {:ok, state}
  end

  def new_session do
    GenServer.call(__MODULE__, :new_session)
  end

  def close_session(session), do: GenServer.call(__MODULE__, {:close_session, session})

  def handle_connect(state) do
    {:noreply, %{state | connected?: true}}
  end

  def handle_close({:abnormal, _reason}, state) do
    {:stop, :abnormal, %{state | connected?: false}}
  end

  def handle_close(_reason, state) do
    {:stop, :normal, %{state | connected?: false}}
  end

  def handle_call(:close_session, _from, %{connected?: false} = state) do
    {:reply, :ok, state}
  end

  def handle_call({:close_session, session}, _from, state) do
    new_state = terminate_session(session, state)
    {:reply, :ok, new_state}
  end

  def handle_call(:new_session, _from, %{connected?: false} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(:new_session, {pid, _ref} = from, state) do
    session_state = %{
      id: state.session_counter,
      owner: pid,
      reply_to: from,
      context_id: nil,
      page_id: nil,
      page_ws_uri: nil,
      monitor_ref: Process.monitor(pid),
    }

    method(state.socket, "Target.createBrowserContext", %{}, session_state.id)
    new_state = put_in(state, [:sessions, session_state.id], session_state)
    method(state.socket, "Browser.getVersion")

    {:noreply, %{new_state | session_counter: state.session_counter + 1}}
  end


  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    session = Enum.find state.sessions, fn {_, session} ->
      session.monitor_ref == ref
    end

    new_state =
      if session do
        terminate_session(elem(session, 1), state)
      else
        state
      end

    {:noreply, new_state}
  end


  def handle_frame(
    {:text,
      %{"id" => session_id, "result" => %{"browserContextId" => context_id}}},
    %{sessions: sessions} = state
  ) do
    session = Map.get(sessions, session_id)
    session = %{session | context_id: context_id}
    request_new_page_for_context(context_id, session, state)

    new_state = put_in(state, [:sessions, session_id], session)
    {:noreply, new_state}
  end

  def handle_frame(
    {:text,
    %{"id" => session_id, "result" => %{"targetId" => page_id}}
    } = frame,
    %{sessions: sessions} = state
  ) do
    Logger.debug("FRAME: #{inspect frame}")
    session = Map.get(sessions, session_id)
    session = %{session | page_id: page_id,
                          page_ws_uri: page_ws_address(state, page_id)}

    GenServer.reply(session.reply_to, {:ok, session})

    new_state = put_in(state, [:sessions, session_id], session)
    {:noreply, new_state}
  end

  def handle_frame(frame, state) do
    Logger.debug("FRAME: #{inspect frame}")
    {:noreply, state}
  end

  defp request_new_page_for_context(context_id, %{id: method_id}, %{socket: socket}) do
    method(
      socket,
      "Target.createTarget",
      %{browserContextId: context_id, url: "about:_blank"},
      method_id
    )
  end

  defp terminate_session(session, %{socket: socket} = state) do
    method(
      socket,
      "Target.closeTarget",
      %{targetId: session.page_id},
      session.id
    )
    method(
      socket,
      "Target.disposeBrowserContext",
      %{browserContextId: session.context_id},
      session.id
    )

    new_sessions = Map.drop(state.sessions, [session.id])
    %{state | sessions: new_sessions}
  end

  defp fetch_controller_socket_address(debugger_address) do
    address = debugger_address |> URI.parse()
    address = %{address | path: "/json"}
    resp = HTTPotion.get(address)

    response =
      case resp do
        %HTTPotion.Response{body: body, status_code: 200} ->
          Poison.decode!(body)
      end

    controller_context = response |> Enum.reverse() |> hd()
    socket_url = Map.get(controller_context, "webSocketDebuggerUrl")

    if socket_url do
      socket_url
    else
      "ws://#{address.host}:#{address.port}/devtools/page/#{controller_context["id"]}"
    end
  end

  defp page_ws_address(%{socket_uri: socket_uri}, page_id) do
    %{socket_uri | path: "/devtools/page/#{page_id}"}
  end

  defp method(socket, meth, params \\ %{}, id \\ nil)
  defp method(socket, meth, params, nil) do
    method(socket, meth, params, 56)
  end

  defp method(socket, meth, params, id) do
    args = %{method: meth, id: id, params: params}
    Logger.debug("Sending method: #{args |> inspect}")
    Socket.Web.send(socket, {:text, Poison.encode!(args)})
  end
end
