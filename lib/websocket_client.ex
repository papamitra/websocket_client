defmodule WebsocketClient do
  use GenServer

  alias WebsocketClient.Frame
  alias WebsocketClient.Util
  alias WebsocketClient.Socket

  @default_port_ws 80
  @default_port_wss 443

  @callback init(any) ::
  {:ok, any}

  @callback handle_text(any, any) ::
  {:ok, any}

  defmodule Message do
    defstruct opcode: nil, payload: <<>>
  end

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour WebsocketClient

      def init(args) do
        {:ok, args}
      end

      def handle_text(_text, state) do
        {:ok, state}
      end

      defoverridable [init: 1, handle_text: 2]
    end
  end

  def start_link(mod, url) do
    GenServer.start_link(__MODULE__, [mod, url])
  end

  def init([mod, url] = args) do

    case apply(mod, :init, [args]) do
      {:ok, mod_state} ->
        {:ok, socket} = url |> URI.parse |> connect
        {:ok, %{mod: mod, socket: socket, remain: <<>>, msg: nil, mod_state: mod_state }}
    end

  end

  def send(pid, data) do
    GenServer.call(pid, {:send, data})
  end

  def connect(%URI{scheme: "ws", host: host, port: port, path: path}) do

    port = port || @default_port_ws

    {:ok, socket} = Socket.Tcp.connect(String.to_charlist(host), port, [{:active, false}])

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

    :ok = socket |> Socket.packet(:raw)
    :ok = socket |> Socket.send(handshake)

    :ok = socket |> Socket.packet(:http_bin)
    {:ok, {:http_response, _, 101, _}} = socket |> Socket.recv(0)
    get_header(socket)

    :ok = socket |> Socket.packet(:raw)
    :ok = socket |> Socket.active()

    {:ok, socket}
  end

  def handle_info({:tcp, _socket, data}, state) do
    %{mod: mod, msg: msg, remain: remain, mod_state: mod_state} = state
    remain = remain <> :erlang.list_to_bitstring(data)

    {frame, remain} = remain |> WebsocketClient.Frame.parse

    if remain != <<>> do
      IO.puts("data remaining")
    end

    case msg |> append_frame(frame) do
      {:ok, new_msg} ->
        case new_msg |> dispatch_message(mod, mod_state) do
          {:ok, new_mod_state} ->
            {:noreply, %{state | remain: remain, msg: nil, mod_state: new_mod_state}}
          _ ->
            {:noreply, state}
        end
      {:cont, new_msg} ->
        {:noreply, %{state | remain: remain, msg: new_msg}}
    end
  end

  def handle_info({_event, _socket, _data}, state) do
    IO.puts("handle_info other")
    state |> IO.inspect

    {:noreply, state}
  end

  def handle_call({:send, data}, _from, %{socket: socket} = state) do
    frame = Frame.create(data)

    # TODO: error
    socket |> Socket.send(frame)

    {:reply, :ok, state}
  end

  # private

  defp get_header(socket) do
    case socket |> Socket.recv(0) do
      {:ok, {:http_header, _, name, _, value}} ->
        "#{name}: #{value}" |> IO.puts
        get_header(socket)
      {:ok, :http_eoh} ->
        :ok
    end
  end

  defp append_frame(%Message{opcode: _opcode, payload: payload} = msg,
      %Frame{fin: 0, opcode: 0, payload: frame_payload}) do
    {:cont, %{msg | payload: payload <> frame_payload}}
  end

  defp append_frame(nil, %Frame{fin: 0, opcode: opcode, payload: payload}) do
    {:cont, %Message{opcode: opcode, payload: payload}}
  end

  defp append_frame(%Message{opcode: _opcode, payload: payload} = msg,
      %Frame{fin: 1, opcode: 0, payload: frame_payload}) do
    {:ok, %{msg | payload: payload <> frame_payload}}
  end

  defp append_frame(nil, %Frame{fin: 1, opcode: opcode, payload: payload}) do
    {:ok, %Message{opcode: opcode, payload: payload}}
  end

  defp dispatch_message(msg, mod, mod_state) do
    case Util.opcode(msg.opcode) do
      :text -> enter_handle_text(msg, mod, mod_state)
      :binary ->
        IO.puts("opcode binary not implemented")
        {:ok, mod_state}
      :close ->
        IO.puts("opcode close not implemented")
        {:ok, mod_state}
      :ping ->
        IO.puts("opcode ping not implemented")
        {:ok, mod_state}
      :pong ->
        IO.puts("opcode pong not implemented")
        {:ok, mod_state}
    end
  end

  defp enter_handle_text(msg, mod, mod_state) do
    apply(mod, :handle_text, [msg.payload, mod_state])
  end

end
