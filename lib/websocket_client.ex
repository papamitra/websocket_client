defmodule WebsocketClient do
  use GenServer

  @default_port_ws 80
  @default_port_wss 443

  def start_link(url) do
    GenServer.start_link(__MODULE__, url)
  end

  def init(url) do
    {:ok, socket} = url |> URI.parse |> connect
    {:ok, %{socket: socket}}
  end

  def connect(%URI{scheme: "ws", host: host, port: port, path: path}) do

    port = port || @default_port_ws

    {:ok, socket} = :gen_tcp.connect(String.to_charlist(host), port, [{:active, false}])

    IO.puts("connect2")

    path = path || "/"
    key = :base64.encode("1234567890123456")

    handshake = [
      "GET #{path} HTTP/1.1", "\r\n",
      "Host: #{host}:#{port}", "\r\n",
      "Upgrade: websocket", "\r\n",
      "Connection: Upgrade", "\r\n",
      "Sec-WebSocket-Key: #{key}", "\r\n",
      "Sec-WebSocket-Version: 13", "\r\n",
      "\r\n"]

    IO.puts(handshake)

    :ok = socket |> :inet.setopts([{:packet, :raw}])
    :ok = socket |> :gen_tcp.send(handshake)

    :ok = socket |> :inet.setopts([{:packet, :http_bin}])
    {:ok, {:http_response, _, 101, _}} = socket |> :gen_tcp.recv(0)

    {:ok, socket}
  end

end
