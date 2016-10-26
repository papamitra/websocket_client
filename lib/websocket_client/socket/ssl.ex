defmodule WebsocketClient.Socket.Ssl do
  defstruct socket: nil

  alias WebsocketClient.Socket.Ssl

  @type t :: %Ssl{socket: port}

  @spec connect(String.t, :inet.port_number, [any]) :: {:ok, t} | {:error, any}
  def connect(address, port, opts) do
    case :ssl.connect(address, port, opts) do
      {:ok, {socket, _}} ->
        {:ok, %Ssl{socket: socket}}
      err ->
        err
    end
  end

  def upgrade_to_ssl(socket) do
    {:ok, sslsocket} = :ssl.connect(socket, [{:active, false}])
    {:ok, %Ssl{socket: sslsocket}}
  end
end
