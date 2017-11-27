defmodule HPDF.Receiver do
  @moduledoc false

  # Receives messages from the raw web socket.
  require Logger

  def start_link({socket, owning_pid}, _opts \\ []) do
    pid = spawn_link(__MODULE__, :listen, [socket, owning_pid, %{}])
    {:ok, pid}
  end

  def listen(socket, owning_pid, state) do
    case Socket.Web.recv(socket) do
      :ok -> {:socket_recv, :ok}
      :close -> {:socket_close, :close}
      {:ok, msg} ->
        Process.send owning_pid, {:socket_recv, {:ok, msg}}, []
        listen socket, owning_pid, state
      {:error, thing} ->
        Process.send owning_pid, {:socket_recv, {:error, thing}}, []
        listen socket, owning_pid, state
      {:close, reason} ->
        Process.send owning_pid, {:socket_close, reason}, []
      msg ->
        Process.send owning_pid, {:socket_recv, {:unknown, msg}}, []
        listen socket, owning_pid, state
    end
  end
end
