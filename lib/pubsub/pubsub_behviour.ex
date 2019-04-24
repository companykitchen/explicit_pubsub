defmodule Pubsub.Behaviour do
  @type topic :: String.t()
  @type server :: atom
  @type msg :: %{topic: topic, event: atom, message: any}

  @macrocallback publish(server, topic, msg) :: Macro.t()
  @callback subscribe(server, topic) :: Macro.t()
  @callback get_child_spec(server) :: Macro.t()
end

defmodule Pubsub.PhoenixPubsub do
  @behaviour Pubsub.Behaviour
  def get_child_spec(server) do
    quote do
      %{
        id: Phoenix.PubSub.PG2,
        start: {Phoenix.PubSub.PG2, :start_link, [unquote(server), []]}
      }
    end
  end

  defmacro publish(server, topic, msg) do
    quote do
      Phoenix.PubSub.broadcast(unquote(server), unquote(topic), unquote(msg))
    end
  end

  def subscribe(server, topic) do
    quote do
      Phoenix.PubSub.subscribe(unquote(server), unquote(topic))
    end
  end
end
