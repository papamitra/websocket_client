defmodule WebsocketClient do
  use GenServer

  @default_port_ws 80
  @default_port_wss 443

  def start_link(url) do
    GenServer.start_link(__MODULE__, url)
  end

  def init(url) do
    {:ok, socket} = url |> URI.parse |> connect
    {:ok, %{socket: socket, remain: <<>>}}
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
    get_header(socket)

    :ok = socket |> :inet.setopts([{:packet, :raw}, {:active, true}])

    {:ok, socket}
  end

  def handle_info({:tcp, socket, msg}, %{remain: remain} = state) do
    IO.puts("handle_info tcp")
    remain = remain <> :erlang.list_to_bitstring(msg)

    {frame, remain} = remain |> WebsocketClient.Frame.parse

    if remain != <<>> do
      IO.puts("data remaining")
    end

    {:noreply, %{state | remain: remain}}
  end

  def handle_info({event, socket, data}, state) do
    IO.puts("handle_info other")
    event |> IO.puts

    {:noreply, state}
  end

  defp get_header(socket) do
    case socket |> :gen_tcp.recv(0) do
      {:ok, {:http_header, _, name, _, value}} ->
        "#{name}: #{value}" |> IO.puts
        get_header(socket)
      {:ok, :http_eoh} ->
        :ok
    end
  end

end
