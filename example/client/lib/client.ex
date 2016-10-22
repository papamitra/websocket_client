defmodule Client do
  use WebsocketClient

  def start_link(url) do
    WebsocketClient.start_link(__MODULE__, url)
  end

  def handle_text(text) do
    IO.puts("handle_text: #{text}")
  end

end
