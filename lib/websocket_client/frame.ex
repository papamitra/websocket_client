defmodule WebsocketClient.Frame do

  defstruct fin: nil, opcode: nil, payload: nil

  def parse(<<fin :: 1,
    0 :: 3,
    opcode :: 4,
    0 :: 1,
    126 :: 7,
    length :: 16,
    payload :: binary-size(length),
    remain :: binary>>) do
    {%WebsocketClient.Frame{fin: fin, opcode: opcode, payload: payload}, remain}
  end

  def parse(<<fin :: 1,
    0 :: 3,
    opcode :: 4,
    0 :: 1,
    127 :: 7,
    length :: 32,
    payload :: binary-size(length),
    remain :: binary>>) do
    {%WebsocketClient.Frame{fin: fin, opcode: opcode, payload: payload}, remain}
  end

  def parse(<<fin :: 1,
    0 :: 3,
    opcode :: 4,
    0 :: 1,
    length :: 7,
    payload :: binary-size(length),
    remain :: binary>>) do
    {%WebsocketClient.Frame{fin: fin, opcode: opcode, payload: payload}, remain}
  end

end
