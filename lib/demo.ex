defmodule Pubsub.Demo do
  @moduledoc "Testing module doc"
  use Pubsub
  @type name_tuple :: {String.t(), String.t()}

  topic "string_events" do
    publishes(:event1, name_tuple)
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

defmodule Pubsub.DemoConsumer do
  use GenServer
  require Pubsub.Demo.StringEvents
  @behaviour Pubsub.Demo.StringEvents

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
  def handle_event1({_string1, _string2}, state) do
    state
  end

  def handle_event2(_string, state) do
    state
  end

  def handle_cast(_, state) do
    {:noreply, state}
  end

  # Handle Calls
  # Handle Casts
  # Pubsub.Demo.StringEvents.route_handle_infos()
  def handle_info("other info", state) do
    {:noreply, state}
  end

  Pubsub.Demo.StringEvents.route_handle_infos()

  def handle_call(_, state) do
    IO.inspect("Just checking")
    {:noreply, state}
  end

  # def handle_info(%{topic: "string_events", event: :event1, msg: msg}, state) do
  #   state = handle_event1(msg, state)
  #   {:noreply, state}
  # end

  # def handle_info(%{topic: "string_events", event: :event2, msg: msg}, state) do
  #   state = handle_event2(msg, state)
  #   {:noreply, state}
  # end
end

defmodule Pubsub.DemoProducer do
  def publish_it() do
    _ = Pubsub.Demo.IntegerEvents.publish_event1(1)
  end
end
