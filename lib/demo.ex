defmodule Pubsub.Demo do
  alias Pubsub.Demo.Types
  @moduledoc "Testing module doc"
  use Pubsub

  topic "string_events" do
    publishes(:event1, Types.name_tuple())
    publishes(:event2, String.t())
  end

  topic "integer_events" do
    publishes(:event1, integer())
    publishes(:event2, integer())
  end

  topic "single_events" do
    publishes(:my_event, %{hello: atom, world: atom})
  end
end

defmodule Pubsub.Demo.Types do
  @type name_tuple :: {String.t(), String.t()}
end

defmodule Pubsub.DemoConsumer do
  use Pubsub.Demo.StringEvents

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # genserver callbacks
  def init(_args) do
    _ = Pubsub.Demo.StringEvents.subscribe(String.t())
    {:ok, %{}}
  end

  ## Event consumers from behaviour
  def handle_string_events_event1({_string1, _string2}, state) do
    state
  end

  def handle_string_events_event2(_string, state) do
    state
  end

  def handle_cast(_, state) do
    {:noreply, state}
  end

  def handle_call(_, state) do
    {:noreply, state}
  end
end

defmodule Pubsub.DemoProducer do
  def publish_it() do
    _ = Pubsub.Demo.IntegerEvents.publish_event1(1)
  end
end
