defmodule HPDF.Controller.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link() do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def start_child(id) do
    Supervisor.start_child(__MODULE__, id: id)
  end

  def init(_args) do
    children = [
      worker(HPDF.Controller, [], restart: :temporary)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
