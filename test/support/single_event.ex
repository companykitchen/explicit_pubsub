defmodule PubsubTest.SingleEvent2 do
  use Pubsub

  topic "integer_events" do
    publishes(:event1, integer())
  end
end
