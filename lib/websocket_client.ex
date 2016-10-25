defmodule WebsocketClient do
  use GenServer

  alias WebsocketClient.Frame
  alias WebsocketClient.Util
  alias WebsocketClient.Socket

  @default_port_ws 80
  @default_port_wss 443

  @callback init(any) ::
  {:ok, any} | :ignore | {:stop, any}

  @callback handle_text(any, any) ::
  {:ok, any} | {:reply, {atom, binary}, any} | {:close, binary, any}

  @callback handle_binary(any,any) ::
  {:ok, any} | {:reply, {atom, binary}, any} | {:close, binary, any}

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

      def handle_binary(_binary, state) do
        {:ok, state}
      end

      defoverridable [init: 1, handle_text: 2, handle_binary: 2]
    end
  end

  @spec start_link(atom, binary) :: {:ok, pid} | :ignore | {:error, any}
  def start_link(mod, url) do
    GenServer.start_link(__MODULE__, [mod, url])
  end

  @spec send(pid, binary) :: any
  def send(pid, data) do
    GenServer.call(pid, {:send, data})
  end

  @spec close(pid, integer) :: :ok
  def close(pid, code) when 0 <= code and code <= 0xffff do
    GenServer.cast(pid, {:close, code})
  end

  # callback function

  def init([mod, url] = args) do
    case apply(mod, :init, [args]) do
      {:ok, mod_state} ->
        {:ok, socket} = url |> URI.parse |> connect
        {:ok, %{status: :inited, mod: mod, socket: socket, remain: <<>>, msg: nil, mod_state: mod_state }}
      {:ok, _mod_state, _timeout} ->
        {:stop, :bad_return_value}
      other ->
        other
    end
  end

  def handle_info({:tcp, _socket, data}, state) do
    %{mod: mod, socket: socket, msg: msg, remain: remain, mod_state: mod_state} = state
    remain = remain <> :erlang.list_to_bitstring(data)

    {frame, remain} = remain |> WebsocketClient.Frame.parse

    if remain != <<>> do
      IO.puts("data remaining")
    end

    case msg |> append_frame(frame) do
      {:ok, new_msg} ->
        case new_msg |> dispatch_message(mod, socket, mod_state) do
          {:ok, new_mod_state} ->
            {:noreply, %{state | remain: remain, msg: nil, mod_state: new_mod_state}}
          _ ->
            {:noreply, state}
        end
      {:cont, new_msg} ->
        {:noreply, %{state | remain: remain, msg: new_msg}}
    end
  end

  def handle_info({:close, code}, %{socket: socket}) do
    socket |> Socket.send({:close, << code :: 16>>})
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

  defp handshake(socket, host, port, path) do
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
  end

  defp connect(%URI{scheme: "ws", host: host, port: port, path: path}) do

    port = port || @default_port_ws

    socket = case System.get_env("http_proxy") |> URI.parse do
               %URI{host: proxy_host, port: proxy_port} when not is_nil(proxy_host) ->
                 proxy_port = proxy_port || 80
                 {:ok, proxy} = Socket.Tcp.connect(String.to_charlist(proxy_host), proxy_port, [{:active, false}])
                 :ok = proxy |> connect_over_proxy(host, port)
                 proxy
               _ ->
                 {:ok, socket} = Socket.Tcp.connect(String.to_charlist(host), port, [{:active, false}])
                 socket
             end

    handshake(socket, host, port, path)

    {:ok, socket}
  end

  defp connect(%URI{scheme: "wss", host: host, port: port, path: path}) do

    port = port || @default_port_wss

    socket = case System.get_env("https_proxy") |> URI.parse do
               %URI{host: proxy_host, port: proxy_port} when not is_nil(proxy_host) ->
                 proxy_port = proxy_port || 443
                 {:ok, proxy} = Socket.Ssl.connect(String.to_charlist(proxy_host), proxy_port, [{:active, false}, {:mode, :binary}])
                 :ok = proxy |> connect_over_proxy(host, port)
                 proxy
               _ ->
                 {:ok, socket} = Socket.Ssl.connect(String.to_charlist(host), port, [{:mode, :binary},
                                                                                     {:active, false}])
                 socket
             end

    handshake(socket, host, port, path)

    {:ok, socket}
  end

  defp connect_over_proxy(socket, host, port) do
    :ok = socket |> Socket.packet(:raw)
    socket |> Socket.send([
      "CONNECT #{host}:#{port} HTTP/1.1", "\r\n",
      "\r\n"])

    socket |> Socket.packet(:http_bin)
    {:ok, {:http_response, _, 200, _}} = socket |> Socket.recv(0)
    {:ok, :http_eoh} = socket |> Socket.recv(0)

    :ok
  end

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

  defp dispatch_message(msg, mod, socket, mod_state) do
    case Util.opcode(msg.opcode) do
      :text ->
        do_handle_text(msg, mod, socket, mod_state)
      :binary ->
        do_handle_binary(msg, mod, socket, mod_state)
      :close ->
        IO.puts("opcode close not implemented")
        # TODO
        exit(:normal)
      :ping ->
        :ok = send_pong(msg, socket)
        {:ok, mod_state}
      :pong ->
        {:ok, mod_state}
    end
  end

  defp send_pong(msg, socket) do
    frame = Frame.create({:pong, msg.payload})
    socket |> Socket.send(frame)
  end

  defp do_handle_text(msg, mod, socket, mod_state) do
    case apply(mod, :handle_text, [msg.payload, mod_state]) do
      {:ok, new_mod_state} ->
        {:ok, new_mod_state}
      {:reply, data, new_mod_state} ->
        frame = Frame.create(data)
        :ok = socket |> Socket.send(frame)
        {:ok, new_mod_state}
      {:close, _new_mode_state} ->
        # TODO
        exit(:normal)
    end
  end

  defp do_handle_binary(msg, mod, socket, mod_state) do
    case apply(mod, :handle_binary, [msg.payload, mod_state]) do
      {:ok, new_mod_state} ->
        {:ok, new_mod_state}
      {:reply, data, new_mod_state} ->
        frame = Frame.create(data)
        :ok = socket |> Socket.send(frame)
        {:ok, new_mod_state}
      {:close, _new_mode_state} ->
        # TODO
        exit(:normal)
    end
  end
end
