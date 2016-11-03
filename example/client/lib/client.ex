defmodule Client do
  use GenServer
  require Logger

  def start_link(url) do
    GenServer.start_link(__MODULE__, [url])
  end

  def init([url]) do
    {:ok, socket} = WebsocketClient.start_link(self, url)
    {:ok, %{socket: socket}}
  end

  def send(pid, text) do
    Kernel.send(pid, {:send, text})
  end

  def handle_info({:recv_text, text}, state) do
    Logger.info "handle_text: #{inspect text}"
    {:noreply, state}
  end

  def handle_info({:send, message}, %{socket: socket} = state) do
    socket |> WebsocketClient.send({:text, message})
    {:noreply, state}
  end

end
