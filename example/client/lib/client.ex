defmodule Client do
  use WebsocketClient

  require Logger

  def start_link(url) do
    :crypto.start()
    :ssl.start()
    WebsocketClient.start_link(__MODULE__, url)
  end

  def send(pid, text) do
    WebsocketClient.send(pid, text)
  end

  def handle_text(text, _state) do
    Logger.info "handle_text: #{text}"
  end

end
