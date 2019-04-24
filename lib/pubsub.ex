defmodule Pubsub do
  alias Pubsub.{Document, PhoenixPubsub}
  # Next Steps:
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

  defmacro topic(string_topic, do: {:__block__, [], actions}) do
    write_topic(string_topic, actions, __CALLER__)
  end

  defmacro topic(string_topic, do: action) do
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
  def namespace_specs(actions, calling_module) do
    namespace =
      calling_module
      |> Module.split()
      |> Enum.map(&String.to_existing_atom(&1))

    Enum.map(actions, fn
      {:publishes, ctx, [event | [args_spec]]} ->
        {:publishes, ctx, [event, [namespace_spec(args_spec, namespace)]]}

      other ->
        other
    end)
  end

  def namespace_spec({atom, ctx, nil}, namespace) do
    {{:., ctx, [{:__aliases__, ctx, namespace}, atom]}, ctx, []}
  end

  def namespace_spec(other, _namespace), do: other

  def write_topic(string_topic, actions, caller) do
    calling_module = caller.module
    actions = namespace_specs(actions, calling_module)

    module_name =
      string_topic
      |> Macro.camelize()

    Module.put_attribute(calling_module, :topics, {string_topic, module_name})
    module_name = String.to_atom("#{calling_module}.#{module_name}")

    attributes =
      for {:publishes, _, [event | [args_spec]]} <- actions do
        quote do
          {unquote(module_name), unquote(event), unquote(Macro.escape(args_spec))}
        end
      end

    publish_functions =
      for {:publishes, _, [event | [[args_spec]]]} <- actions do
        fn_name = String.to_atom("publish_#{event}")

        doc = Document.publish_function(event, string_topic, args_spec)

        quote do
          @doc unquote(doc)
          @spec unquote(fn_name)(unquote(args_spec)) :: :ok | {:error, term}
          def unquote(fn_name)(arg) do
            msg = Pubsub.make_envelope(unquote(string_topic), unquote(event), arg)

            PhoenixPubsub.publish(unquote(calling_module), unquote(string_topic), msg)
          end
        end
      end

    basic_subscribe = Pubsub.PhoenixPubsub.subscribe(calling_module, string_topic)

    subscribe_fn =
      quote do
        defmacro subscribe(type) do
          Module.put_attribute(
            __CALLER__.module,
            :before_compile,
            {Pubsub, :before_compile_subscribe}
          )

          Module.register_attribute(__CALLER__.module, :subscriptions, accumulate: true)
          Module.put_attribute(__CALLER__.module, :state_type, type)

          for {module, event, arg_spec} <- @events do
            Module.put_attribute(
              __CALLER__.module,
              :subscriptions,
              {module, event, arg_spec}
            )
          end

          caller = __CALLER__.module

          calling_module = unquote(calling_module)
          string_topic = unquote(string_topic)

          PhoenixPubsub.subscribe(unquote(calling_module), unquote(string_topic))
        end

        def subscribe() do
          unquote(basic_subscribe)
        end
      end

    moduledoc = Document.topic_module(calling_module, string_topic, actions)

    callbacks =
      for {:publishes, _, [event | [[args_spec]]]} <- actions do
        callback = String.to_atom("handle_#{event}")

        quote do
          @callback unquote(callback)(unquote(args_spec), any()) :: any()
        end
      end

    events =
      for {:publishes, _, [event | _]} <- actions do
        event
      end

    quote do
      defmodule unquote(module_name) do
        @moduledoc unquote(moduledoc)
        @events unquote(attributes)
        import Pubsub
        unquote(callbacks)
        unquote(publish_functions)
        unquote(subscribe_fn)

        defmacro route_handle_infos() do
          string_topic = unquote(string_topic)

          for event <- unquote(events) do
            callback = String.to_atom("handle_#{event}")

            quote do
              def handle_info(
                    %{topic: unquote(string_topic), event: unquote(event), message: msg},
                    state
                  ) do
                new_state = unquote(callback)(msg, state)
                {:noreply, new_state}
              end
            end
          end
        end
      end
    end
  end

  defmacro document(env) do
    module_name = inspect(env.module)
    topics = Module.get_attribute(env.module, :topics)
    moduledoc = Document.main_module(module_name, topics)

    Module.put_attribute(env.module, :moduledoc, {99, moduledoc})
  end

  defmacro before_compile_subscribe(context) do
    # TODO, still working out how to define the callbacks module
    events = Module.get_attribute(context.module, :subscriptions)
    state_type = Module.get_attribute(context.module, :state_type)

    IO.puts("State type is #{inspect(Macro.to_string(state_type))}")

    all = Enum.group_by(events, &elem(&1, 0), fn {_, e, s} -> {e, s} end)

    for {_m, events} <- all do
      for {event, [spec]} <- events do
        function = String.to_atom("handle_#{event}")

        quote do
          @callback unquote(function)(unquote(spec), unquote(state_type)) :: unquote(state_type)
        end
      end
    end
  end
end
