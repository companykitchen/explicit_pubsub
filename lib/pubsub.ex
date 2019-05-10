defmodule Pubsub do
  alias Pubsub.{Document, PhoenixPubsub}
  # Next Steps:
  #   When changing an event, is it possible to also flag the
  #      handle_topic_event functions?
  # Generate the behaviour by
  #   When subscribe/1 is called in a client module
  #   Register a before_compile attribute
  #   Register that modules type argument
  #   *** In teh before_compile, create the behaviour and register it
  #  TODO - currently the behaviour is generated in the source module with a state type of any
  #    and in the client module with the state type.  Decide if the client module neads a seperate module
  #    for the behaviour, and if so, create it, and only include one behaviour
  # Also - allow both Phoenix Pubsub and Registery

  @moduledoc """
  You would include this with a use PubSub in your module, and from there,
  you would describe what topics & messages you published
  i.e.
  The envelope will always be
  %{
    topic: "payments",
    event: :payment_declined,
    message: ...
  }
  Each topic is it's own module

  Blaster.PubSub.topic "payments" do
   publishes(:payment_declined, use_envelope: true, message: {Purchase.payment(), CCGatewayResponse.response()})
   publishes(:payment_accepted, use_envelope: true, message: {Purchase.payment(), CCGatewayResponse.response()})
  end

  would result in
  __MODULE__.Payments.payment_declined(map)
  and
  __MODULE__.Payments.payment_accepted(map)
  and
  __MOUDLE__.Payments.subscribe()
  """

  @type name :: atom
  @type spec :: any
  @type event :: {name, spec}
  @type topic :: %{
          pubsub_module: module,
          topic: String.t(),
          module: module(),
          events: [event]
        }

  defmacro __using__(_) do
    Module.register_attribute(
      __CALLER__.module,
      :topics,
      accumulate: true,
      persist: false
    )

    quote do
      import Pubsub
      require Pubsub.PhoenixPubsub

      @before_compile {Pubsub, :document}

      def child_spec(arg) do
        unquote(PhoenixPubsub.get_child_spec(__CALLER__.module))
      end
    end
  end

  defmacro topic(string_topic, args \\ [], block)

  defmacro topic(string_topic, _args, do: {:__block__, [], actions}) do
    write_topic(string_topic, actions, __CALLER__)
  end

  defmacro topic(string_topic, _args, do: action) do
    write_topic(string_topic, [action], __CALLER__)
  end

  defmacro make_envelope(topic, event, msg) do
    quote do
      %{
        topic: unquote(topic),
        event: unquote(event),
        message: unquote(msg)
      }
    end
  end

  # Ensures that if specs contain custom types that are defined in the
  # top-level module, that they are aliased
  def namespace_specs(actions, caller) do
    for {:publishes, _ctx, [event | [arg_spec]]} <- actions do
      {event, namespace_spec(arg_spec, caller)}
    end
  end

  def namespace_spec(ast, caller) do
    # First, put the calling module as the namespace
    # for any type that is missing one
    ast =
      Macro.prewalk(ast, fn
        {atom, ctx, nil} ->
          {{:., ctx, [{:__aliases__, ctx, caller.module}, atom]}, ctx, []}

        other ->
          other
      end)

    Macro.prewalk(ast, fn x -> Macro.expand(x, caller) end)
  end

  def write_topic(string_topic, actions, caller) do
    module_name =
      string_topic
      |> Macro.camelize()

    topic = %{
      pubsub_module: caller.module,
      topic: string_topic,
      module: String.to_atom("#{caller.module}.#{module_name}"),
      events: namespace_specs(actions, caller)
    }

    Module.put_attribute(caller.module, :topics, topic)

    Pubsub.TopicModule.write_module(topic)
  end

  # Invoked by before_compile
  defmacro document(env) do
    module_name = inspect(env.module)
    topics = Module.get_attribute(env.module, :topics)
    moduledoc = Document.main_module(module_name, topics)

    Module.put_attribute(env.module, :moduledoc, {99, moduledoc})
  end
end
