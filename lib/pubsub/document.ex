defmodule Pubsub.Document do
  def publish_function(event, string_topic, args_spec) do
    """
    Publishes the #{inspect(event)} message to the #{inspect(string_topic)} topic.
    The actual message published will be:
    ```
    %{ topic: #{inspect(string_topic)},
       event: #{inspect(event)},
       msg: #{Macro.to_string(args_spec)} }
    ```
    """
  end

  def topic_module(calling_module, string_topic, actions) do
    moduledoc =
      for {:publishes, _, [event | [args_spec]]} <- actions do
        "`publish_#{event}/1` takes a `#{Macro.to_string(args_spec)}` and publishes  `%{topic: #{
          inspect(string_topic)
        }, event: #{inspect(event)}, msg: #{Macro.to_string(args_spec)}}`\n\n"
      end
      |> Enum.join()

    "Publishes events on the `#{inspect(calling_module)}`'s topic: #{inspect(string_topic)}\n\n" <>
      "You can subscribe to events by calling `subscribe/1`\n\n" <> moduledoc
  end

  def main_module(module_name, topics) do
    defined =
      for {topic, module} <- topics do
        "topic `#{topic}` is handled by the module `#{module_name}.#{module}`\n"
      end

    defined = if defined == [], do: "none", else: Enum.join(defined, "\n")

    """
    # Sets up a publishing hub for `#{module_name}`
    The currently defined topics are:

    #{defined}

    ## How to use
    #{module_name} acts as a publishing/subscription domain.  To use, you must first define a topic within
    this module.  e.g.
    ```
    topic "string_events" do
      publishes(:event1, {String.t(), String.t()})
      publishes(:event2, String.t())
    end
    ```
    Which would define a topic called `"string_events"` that would publish two events.
    `:event1` is a tuple of two strings.
    `:event2` is a single string.

    A Topic's actions are handled in a submodule which is generated by camelizing the topic name,
    and defining publishing functions in the form of `publish_<event name>(arg).  So in the above
    example, the publish and subscribe functions will be created in the `#{module_name}.StringEvents` module.

    To publish an `event1`, you would `#{module_name}.StringEvents.publish_event1({"Hello", "World"})`

    To receive events from `#{module_name}.StringEvents` you would subscribe by: `#{module_name}.StringEvents.subscribe()`

    The generated documentation for `#{module_name}.StringEvents` will have the particulars for those functions

    ## How to start in your application
    Before you can use #{module_name}, you must add the following to your list of child workers
    ```
    %{
      id: Phoenix.PubSub.PG2,
      start: {Phoenix.PubSub.PG2, :start_link, [#{module_name}, []]}
    }
    ```
    """
  end
end
