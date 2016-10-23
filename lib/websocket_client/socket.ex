defmodule WebsocketClient.Socket do
  alias WebsocketClient.Socket.Protocol
  @type t :: Protocol.t

  defdelegate send(self, data), to: Protocol
  defdelegate recv(self, size), to: Protocol
  defdelegate active(self), to: Protocol
  defdelegate packet(self, mode), to: Protocol
end

defprotocol WebsocketClient.Socket.Protocol do

  @spec send(t, any) :: :ok | {:error, any}
  def send(self, data)

  @spec recv(t, integer) :: {:ok, any} | {:error, term}
  def recv(self, size)

  @spec active(t) :: :ok | {:error, term}
  def active(self)

  @spec packet(t, atom) :: :ok | {:error, term}
  def packet(self, mode)

end

defimpl WebsocketClient.Socket.Protocol, for: WebsocketClient.Socket.Tcp do
  alias WebsocketClient.Socket.Tcp

  def send(%Tcp{socket: socket}, data) do
    socket |> :gen_tcp.send(data)
  end

  def recv(%Tcp{socket: socket}, size) do
    socket |> :gen_tcp.recv(size)
  end

  def active(%Tcp{socket: socket}) do
    socket |> :inet.setopts([{:active, true}])
  end

  def packet(%Tcp{socket: socket}, mode) do
    socket |> :inet.setopts([{:packet, mode}])
  end

end

defimpl WebsocketClient.Socket.Protocol, for: WebsocketClient.Socket.Ssl do
  alias WebsocketClient.Socket.Ssl

  def send(%Ssl{socket: socket}, data) do
    socket |> :ssl.send(data)
  end

  def recv(%Ssl{socket: socket}, size) do
    socket |> :ssl.recv(size)
  end

  def active(%Ssl{socket: socket}) do
    socket |> :ssl.setopts([{:active, true}])
  end

  def packet(%Ssl{socket: socket}, mode) do
    socket |> :ssl.setopts([{:packet, mode}])
  end

end
