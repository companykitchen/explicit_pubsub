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
      docs = Code.fetch_docs(SingleEvent)
      assert_receive(%{event: :event1, message: 2, topic: "integer_events"})
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
      alias PubsubTest.{SingleEvent, SpecTest}
      assert Code.ensure_loaded?(SpecTest)
      # TODO - is there a way to pull the specs and make sure that they are valid?
    end
  end
end
