defmodule HPDF.Controller do
  @moduledoc false

  # The controller is the entry point
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def start_link(args, _opts) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(_) do
    {:ok, %{}}
  end

  def print_pdf!(url, opts \\ []) do
    {:ok, pid} = HPDF.Controller.Supervisor.start_child([])
    timeout = Keyword.get(opts, :timeout, :infinity)
    result = GenServer.call(pid, {:print_pdf, url, opts}, timeout)
    GenServer.stop(pid, :normal)
    result
  end

  def handle_call({:print_pdf, url, opts}, _from, state) do
    case HPDF.Browser.new_session() do
      {:ok, session} ->
        result = HPDF.Printer.print_page!(session.page_ws_uri, url, opts)
        HPDF.Browser.close_session(session)
        {:reply, result, state}
      {:error, _reason} = err -> err
    end
  end
end
