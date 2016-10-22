defmodule WebsocketClient.Util do
  Enum.each [ text: 0x1, binary: 0x2, close: 0x8, ping: 0x9, pong: 0xA ], fn { name, code } ->
    def opcode(unquote(name)), do: unquote(code)
    def opcode(unquote(code)), do: unquote(name)
  end
end
