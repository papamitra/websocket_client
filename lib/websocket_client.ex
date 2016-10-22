defmodule WebsocketClient do
  use GenServer

  alias WebsocketClient.Frame

  @default_port_ws 80
  @default_port_wss 443

  @callback handle_recv(any) :: :ok

  defmodule Message do
    defstruct opcode: nil, payload: <<>>
  end

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour WebsocketClient

      def handle_text(payload) do
        :ok
      end

      defoverridable [handle_text: 1]
    end
  end

  def start_link(mod, url) do
    GenServer.start_link(__MODULE__, [mod, url])
  end

  def init([mod, url]) do
    {:ok, socket} = url |> URI.parse |> connect
    {:ok, %{mod: mod, socket: socket, remain: <<>>, msg: nil }}
  end

  def connect(%URI{scheme: "ws", host: host, port: port, path: path}) do

    port = port || @default_port_ws

    {:ok, socket} = :gen_tcp.connect(String.to_charlist(host), port, [{:active, false}])

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

  def handle_info({:tcp, socket, data}, state) do
    %{mod: mod, msg: msg, remain: remain} = state
    remain = remain <> :erlang.list_to_bitstring(data)

    {frame, remain} = remain |> WebsocketClient.Frame.parse

    if remain != <<>> do
      IO.puts("data remaining")
    end

    case msg |> append_frame(frame) do
      {:ok, new_msg} ->
        new_msg |> dispatch_message(mod)
        {:noreply, %{state | remain: remain, msg: nil}}
      {:cont, new_msg} ->
        {:noreply, %{state | remain: remain, msg: new_msg}}
    end
  end

  def handle_info({event, socket, data}, state) do
    IO.puts("handle_info other")
    state |> IO.inspect

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

  defp append_frame(%Message{opcode: opcode, payload: payload} = msg,
      %Frame{fin: 0, opcode: 0, payload: frame_payload}) do
    {:cont, %{msg | payload: payload <> frame_payload}}
  end

  defp append_frame(nil, %Frame{fin: 0, opcode: opcode, payload: payload}) do
    {:cont, %Message{opcode: opcode, payload: payload}}
  end

  defp append_frame(%Message{opcode: opcode, payload: payload} = msg,
      %Frame{fin: 1, opcode: 0, payload: frame_payload}) do
    {:ok, %{msg | payload: payload <> frame_payload}}
  end

  defp append_frame(nil, %Frame{fin: 1, opcode: opcode, payload: payload}) do
    {:ok, %Message{opcode: opcode, payload: payload}}
  end

  Enum.each [ text: 0x1, binary: 0x2, close: 0x8, ping: 0x9, pong: 0xA ], fn { name, code } ->
    defp opcode(unquote(name)), do: unquote(code)
    defp opcode(unquote(code)), do: unquote(name)
  end

  defp dispatch_message(msg, mod) do
    case opcode(msg.opcode) do
      :text -> enter_handle_text(msg, mod)
      :binary ->
        IO.puts("opcode binary not implemented")
      :close ->
        IO.puts("opcode close not implemented")
      :ping ->
        IO.puts("opcode ping not implemented")
      :pong ->
        IO.puts("opcode pong not implemented")
    end

    :ok
  end

  defp enter_handle_text(msg, mod) do
    apply(mod, :handle_text, [msg.payload])
  end

end
