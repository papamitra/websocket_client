defmodule WebsocketClient.Frame do

  alias WebsocketClient.Util
  alias WebsocketClient.Frame

  defstruct fin: nil, opcode: nil, payload: nil

  @type t :: %Frame{ fin: byte, opcode: byte, payload: binary}

  require Logger

  def parse(data) when bit_size(data) < 32 do
    :too_short
  end

  def parse(<<fin :: 1,
    0 :: 3,
    opcode :: 4,
    0 :: 1,
    126 :: 7,
    length :: 16,
    data :: binary>>) do

    case byte_size(data) >= length do
      true ->
        << payload :: binary-size(length), remain :: binary>> = data
        {:ok, {%WebsocketClient.Frame{fin: fin, opcode: opcode, payload: payload}, remain}}
      false ->
        :too_short
    end
  end

  def parse(<<fin :: 1,
    0 :: 3,
    opcode :: 4,
    0 :: 1,
    127 :: 7,
    length :: 32,
    data :: binary >>) do

    case byte_size(data) >= length do
      true ->
        << payload :: binary-size(length), remain :: binary>> = data
        {:ok, {%WebsocketClient.Frame{fin: fin, opcode: opcode, payload: payload}, remain}}
      false ->
        :too_short
    end
  end

  def parse(<<fin :: 1,
    0 :: 3,
    opcode :: 4,
    0 :: 1,
    length :: 7,
    data :: binary>>) do

    case byte_size(data) >= length do
      true ->
        << payload :: binary-size(length), remain :: bitstring>> = data
        {:ok, {%WebsocketClient.Frame{fin: fin, opcode: opcode, payload: payload}, remain}}
      false ->
        :too_short
    end
  end

  def create({opcode, data}) when byte_size(data) > 0xffff do
    << 1 :: 1,
      0 :: 3,
      Util.opcode(opcode) :: 4,
      1 :: 1,
      127 :: 7,
      byte_size(data) :: 64,
      0 :: 32, # TODO
      data :: binary >>
  end

  def create({opcode, data}) when byte_size(data) > 125 do
    << 1 :: 1,
      0 :: 3,
      Util.opcode(opcode) :: 4,
      1 :: 1,
      126 :: 7,
      byte_size(data) :: 16,
      0 :: 32, # TODO
      data :: binary >>
  end

  def create({opcode, data}) do
    << 1 :: 1,
      0 :: 3,
      Util.opcode(opcode) :: 4,
      1 :: 1,
      byte_size(data) :: 7,
      0 :: 32, # TODO
      data :: binary >>
  end

end
