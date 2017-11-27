defmodule HPDF.WebSocket do
  @moduledoc false

  # Converts web socket callbacks into something more useful

  defmacro __using__(_opts \\ []) do
    quote do
      use GenServer

      require Logger

      alias HPDF.Receiver

      def start_link(args, options \\ []) do
        GenServer.start_link(__MODULE__, args, options)
      end

      def start(args, options \\ []) do
        GenServer.start(__MODULE__, args, options)
      end

      def init(args) do
        socket_args = Keyword.fetch!(args, :socket_args)
        with {:ok, socket} <- apply(Socket.Web, :connect, socket_args) do
          {:ok, receiver} = Receiver.start_link({socket, self()})
          Process.send_after(self(), :on_connect, 10)
          {:ok, %{socket: socket, receiver: receiver, args: args}}
        end
      end

      def send_frame(pid, frame) do
        GenServer.cast(pid, {:send_frame, frame})
      end

      defp do_send_frame(socket, frame) do
        Socket.Web.send(socket, frame)
      end

      def close(socket) do
        Socket.Web.close(socket)
      end

      def handle_cast({:send_frame, frame}, %{socket: socket} = state) do
        do_send_frame(socket, frame)
        {:noreply, state}
      end

      def handle_info(:on_connect, state), do: handle_connect(state)

      def handle_info({:socket_recv, :ok}, state), do: {:noreply, state}

      def handle_info({:socket_close, reason}, state), do: handle_close(reason, state)
      def handle_info({:socket_recv, :ok}, state), do: {:noreply, state}
      def handle_info({:socket_recv, {:ok, {:text, msg}}}, state) do
        body = Poison.decode!(msg)
        handle_frame({:text, body}, state)
      end

      def handle_info({:socket_recv, {:ok, {:close, :abnormal, reason}}}, state) do
        handle_close({:abnormal, reason}, state)
      end

      def handle_info({:socket_recv, {:error, :ebadf}}, state), do: {:stop, :lost_connection}
      def handle_info({:socket_recv, {:error, reason}}, state), do: handle_error(reason, state)

      def handle_connect(state), do: {:noreply, state}
      def handle_frame(_msg, state), do: {:noreply, state}
      def handle_error(_reason, state), do: {:noreply, state}
      def handle_close(:close, state), do: {:exit, :normal}
      def handle_close({:abnormal, reason}, state), do: {:exit, :abnormal}
      def handle_close(_msg, state), do: {:exit, :normal}

      defoverridable start_link: 1,
                     start_link: 2,
                     handle_connect: 1,
                     handle_frame: 2,
                     handle_error: 2,
                     handle_close: 2,
                     init: 1
    end
  end
end
