defmodule PubsubTest do
  use ExUnit.Case
  doctest Pubsub

  setup_all do
    defmodule SingleEvent do
      use Pubsub

      topic "integer_events" do
        publishes(:event1, integer())
      end
    end

    defmodule SpecTest do
      use Pubsub
      @type test_type :: {String.t(), String.t()}

      topic "string_events" do
        publishes(:event1, test_type)
      end
    end

    :ok
  end

  setup do
    start_supervised!(PubsubTest.SingleEvent, [])

    :ok
  end

  describe "single event" do
    setup do
      :ok
    end

    test "publish function is defined" do
      alias PubsubTest.SingleEvent
      assert Code.ensure_loaded?(SingleEvent)
      functions = SingleEvent.IntegerEvents.__info__(:functions)
      assert {:publish_event1, 1} in functions
      assert {:subscribe, 0} in functions
    end

    test "Event is published" do
      alias PubsubTest.SingleEvent
      assert Code.ensure_loaded?(SingleEvent)
      SingleEvent.IntegerEvents.subscribe()
      SingleEvent.IntegerEvents.publish_event1(2)
      _docs = Code.fetch_docs(SingleEvent)
      assert_receive(%{event: :event1, message: 2, topic: "integer_events"})
    end

    test "Subscribe creates callbacks" do
      alias PubsubTest.SingleEvent
      assert Code.ensure_loaded?(SingleEvent)

      defmodule IntegerEventsTestModule do
        require PubsubTest.SingleEvent.IntegerEvents
        alias PubsubTest.SingleEvent.IntegerEvents
        @type t :: map
        def init(_args) do
          IntegerEvents.subscribe(t())
        end

        def handle_integer_events_event1(_arg, state) do
          state
        end
      end

      assert Code.ensure_loaded?(PubsubTest.IntegerEventsTestModule)

      assert IntegerEventsTestModule.IntegerEventsBehaviour.behaviour_info(:callbacks) == [
               handle_integer_events_event1: 2
             ]
    end

    test "Subscribe using works" do
      alias PubsubTest.SingleEvent
      assert Code.ensure_loaded?(SingleEvent)

      defmodule UseIntegerEventsTestModule do
        use GenServer
        use PubsubTest.SingleEvent.IntegerEvents

        def start_link(test_pid), do: GenServer.start_link(__MODULE__, test_pid)

        @type t :: %{test_process: pid}
        def init(pid) do
          IntegerEvents.subscribe(t)
          {:ok, %{test_process: pid}}
        end

        def handle_integer_events_event1(arg, state) do
          _ = send(state.test_process, {:handle_integer_events_event1, arg})
          state
        end
      end

      assert(Code.ensure_loaded?(PubsubTest.UseIntegerEventsTestModule))
      start_supervised!({UseIntegerEventsTestModule, self()})
      SingleEvent.IntegerEvents.publish_event1(9)
      assert_receive({:handle_integer_events_event1, 9})
    end

    test "Subscribe multiple times using" do
      alias PubsubTest.SingleEvent
      alias PubsubTest.SpecTest
      assert Code.ensure_loaded?(SingleEvent)

      defmodule UseIntegerEventsTestMultipleModule do
        use GenServer
        use PubsubTest.SingleEvent.IntegerEvents
        use PubsubTest.SpecTest.StringEvents

        def start_link(test_pid), do: GenServer.start_link(__MODULE__, test_pid)

        @type t :: %{test_process: pid}
        def init(pid) do
          IntegerEvents.subscribe(t)
          StringEvents.subscribe(t)
          {:ok, %{test_process: pid}}
        end

        def handle_integer_events_event1(arg, state) do
          _ = send(state.test_process, {:handle_integer_events_event1, arg})
          state
        end

        def handle_string_events_event1(arg, state) do
          _ = send(state.test_process, {:handle_string_events_event1, arg})
          state
        end
      end

      assert(Code.ensure_loaded?(PubsubTest.UseIntegerEventsTestMultipleModule))
      start_supervised!(PubsubTest.SpecTest, [])
      start_supervised!({UseIntegerEventsTestMultipleModule, self()})
      SingleEvent.IntegerEvents.publish_event1(9)
      SpecTest.StringEvents.publish_event1("hello")

      assert_receive({:handle_integer_events_event1, 9})
      assert_receive({:handle_string_events_event1, "hello"})
    end

    test "Docs are created" do
      # Docs are read from a beam file, so this test requires that the beam file be written out
      # Other to-dos see Pubsub.ex
      alias PubsubTest.SingleEvent2
      assert Code.ensure_loaded?(SingleEvent2)
      docs = Code.fetch_docs(SingleEvent2)
      assert {_, _, :elixir, "text/markdown", %{"en" => docs}, _, _} = docs
    end
  end

  describe "specs" do
    test "specs are on the publish functions" do
      alias PubsubTest.SpecTest
      assert Code.ensure_loaded?(SpecTest)
      # TODO - is there a way to pull the specs and make sure that they are valid?
    end
  end
end
