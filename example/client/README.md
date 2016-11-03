# WebsocketClient Example

```iex
$ iex -S mix
iex(1)> {:ok, pid} = Client.start_link("ws://ws.websocketstest.com/service")
12:19:30.366 [info]  handle_text: "connected,"
iex(2)> pid |> Client.send("version,")
12:19:38.959 [info]  handle_text: "version,hybi-draft-13"
```
