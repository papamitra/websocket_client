# WebsocketClient

Elixir Websocket Client

## Installation

the package can be installed as:

  1. Add `websocket_client` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:websocket_client, github: "papamitra/websocket_client"}]
    end
    ```

  2. Ensure `websocket_client` is started before your application:

    ```elixir
    def application do
      [applications: [:websocket_client]]
    end
    ```

