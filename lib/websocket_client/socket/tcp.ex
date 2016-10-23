defmodule WebsocketClient.Socket.Tcp do
  defstruct socket: nil

  alias WebsocketClient.Socket.Tcp

  @type t :: %Tcp{socket: port}

  @spec connect(String.t, :inet.port_number, [any]) :: {:ok, t} | {:error, any}
  def connect(address, port, opts) do
    case :gen_tcp.connect(address, port, opts) do
      {:ok, socket} ->
        {:ok, %Tcp{socket: socket}}
      err ->
        err
    end
  end

end
