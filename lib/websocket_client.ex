defmodule WebsocketClient do
  use GenServer

  alias WebsocketClient.Frame
  alias WebsocketClient.Util
  alias WebsocketClient.Socket

  require Logger

  @default_port_ws 80
  @default_port_wss 443

  defmodule Message do
    defstruct opcode: nil, payload: <<>>
  end

  @spec start_link(pid, binary) :: {:ok, pid} | :ignore | {:error, any}
  def start_link(recv_pid, url) do
    GenServer.start_link(__MODULE__, [recv_pid, url])
  end

  @spec send(pid, {atom, binary}) :: any
  def send(pid, data) do
    GenServer.call(pid, {:send, data})
  end

  @spec close(pid, integer) :: :ok
  def close(pid, code) when 0 <= code and code <= 0xffff do
    GenServer.cast(pid, {:close, code})
  end

  # callback function

  def init([recv_pid, url]) do
     case url |> URI.parse |> connect do
       {:ok, socket} ->
         {:ok, %{status: :inited, recv_pid: recv_pid, socket: socket, remain: <<>>, msg: nil}}
      other ->
        other
    end
  end

  def handle_info({:tcp, _socket, data}, state) when is_list(data) do
    handle_recv(:erlang.list_to_binary(data), state)
  end

  def handle_info({:tcp, _socket, data}, state) do
    handle_recv(data, state)
  end

  def handle_info({:ssl, _socket, data}, state) when is_list(data) do
    handle_recv(:erlang.list_to_binary(data), state)
  end

  def handle_info({:ssl, _socket, data}, state) do
    handle_recv(data, state)
  end

  def handle_info({:close, code}, %{socket: socket}) do
    socket |> Socket.send({:close, << code :: 16>>})
  end

  def handle_info({event, _socket, _data}, state) do
    Logger.warn "handle_info other: #{inspect event}"

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

    Logger.debug handshake

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

    socket = case (System.get_env("http_proxy") || "") |> URI.parse do
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

    {:ok, socket} = case (System.get_env("https_proxy") || "") |> URI.parse do
                      %URI{host: proxy_host, port: proxy_port} when not is_nil(proxy_host) ->
                        proxy_port = proxy_port || 443
                        {:ok, socket} = Socket.Tcp.connect(String.to_charlist(proxy_host), proxy_port, [{:active, false}])
                        :ok = socket |> connect_over_proxy(host, port)
                        socket.socket |> Socket.Ssl.upgrade_to_ssl
                      _ ->
                        Socket.Ssl.connect(String.to_charlist(host), port, [{:mode, :binary},
                                                                            {:active, false}])
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
        Logger.debug "#{name}: #{value}"
        get_header(socket)
      {:ok, :http_eoh} ->
        :ok
    end
  end

  defp handle_recv(data, state) do
    %{recv_pid: recv_pid, socket: socket, msg: msg, remain: remain} = state
    remain = remain <> data

    try do
      case remain |> WebsocketClient.Frame.parse do
        {:ok, {frame, remain}} ->
          case msg |> append_frame(frame) do
            {:ok, new_msg} ->
              new_msg |> dispatch_message(recv_pid, socket)
              handle_recv(<<>>, %{state | remain: remain, msg: nil})
            {:cont, new_msg} ->
              handle_recv(<<>>, %{state | remain: remain, msg: new_msg})
          end
        :too_short ->
          {:noreply, %{state | remain: remain}}
      end
    rescue
      error ->
        Logger.warn "frame parse failed: #{inspect error}"
        {:noreply, %{state | remain: <<>>, msg: nil}}
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

  defp dispatch_message(msg, recv_pid, socket) do
    case Util.opcode(msg.opcode) do
      :text ->
        send_recv_text(msg, recv_pid)
      :binary ->
        send_recv_binary(msg, recv_pid)
      :close ->
        Logger.warn "opcode close not implemented"
        # TODO
        exit(:normal)
      :ping ->
        send_pong(msg, socket)
      :pong ->
        :ok
    end
  end

  defp send_pong(msg, socket) do
    frame = Frame.create({:pong, msg.payload})
    socket |> Socket.send(frame)
  end

  defp send_recv_text(msg, recv_pid) do
    recv_pid |> Kernel.send({:recv_text, msg.payload})
  end

  defp send_recv_binary(msg, recv_pid) do
    recv_pid |> Kernel.send({:recv_binary, msg.payload})
  end
end
