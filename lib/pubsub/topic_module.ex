defmodule Pubsub.TopicModule do
  alias Pubsub.Document
  alias Pubsub.PhoenixPubsub

  def write_module(topic) do
    callbacks = callbacks(topic)
    publish_functions = publish_functions(topic)
    moduledoc = Document.topic_module(topic)
    subscribe_fn = subscribe_fn(topic)
    string_topic = topic.topic

    quote do
      defmodule unquote(topic.module) do
        @moduledoc unquote(moduledoc)
        import Pubsub
        unquote(callbacks)
        unquote(publish_functions)
        unquote(subscribe_fn)

        defmacro route_handle_infos() do
          string_topic = unquote(string_topic)

          for {event, _} <- unquote(Macro.escape(topic.events)) do
            callback = String.to_atom("handle_#{string_topic}_#{event}")

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

        defmacro __using__([]) do
          module = unquote(topic.module)
          caller_module = __CALLER__.module
          Module.register_attribute(__CALLER__.module, :should_subscribe, accumulate: true)

          Module.get_attribute(__CALLER__.module, :should_subscribe)

          if Module.get_attribute(__CALLER__.module, :should_subscribe) == [] do
            Module.put_attribute(
              __CALLER__.module,
              :after_compile,
              {Pubsub.TopicModule, :after_compile_use}
            )
          end

          quote do
            alias unquote(module)
            unquote(module).route_handle_infos()
          end
        end
      end
    end
  end

  def callbacks(%{events: events}) do
    for {event, args_spec} <- events do
      callback = String.to_atom("handle_#{event}")

      quote do
        @callback unquote(callback)(unquote(args_spec), any()) :: any()
      end
    end
  end

  def publish_functions(%{events: events, topic: string_topic, pubsub_module: calling_module}) do
    for {event, args_spec} <- events do
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
  end

  def subscribe_fn(topic) do
    string_topic = topic.topic
    calling_module = topic.pubsub_module
    basic_subscribe = Pubsub.PhoenixPubsub.subscribe(calling_module, string_topic)

    quote do
      defmacro subscribe(type) do
        Module.register_attribute(__CALLER__.module, :subscriptions, accumulate: true)

        if Module.get_attribute(__CALLER__.module, :state_type) == nil do
          Module.put_attribute(
            __CALLER__.module,
            :before_compile,
            {Pubsub.TopicModule, :before_compile_subscribe}
          )

          Module.put_attribute(__CALLER__.module, :state_type, type)
        end

        Module.put_attribute(__CALLER__.module, :subscriptions, unquote(Macro.escape(topic)))

        calling_module = unquote(calling_module)
        string_topic = unquote(string_topic)

        PhoenixPubsub.subscribe(unquote(calling_module), unquote(string_topic))
      end

      def subscribe() do
        unquote(basic_subscribe)
      end
    end
  end

  defmacro before_compile_subscribe(context) do
    topics = Module.get_attribute(context.module, :subscriptions)

    state_type =
      context.module
      |> Module.get_attribute(:state_type)
      |> alias_state_type(context.module)

    for topic <- topics do
      make_callback_module(context.module, state_type, topic)
    end
  end

  def after_compile_use(env, _module) do
    subscribed = Module.get_attribute(env.module, :subscriptions) || []

    should_subscribe = Module.get_attribute(env.module, :should_subscribe)

    not_subscribed =
      Enum.reject(should_subscribe, &Enum.any?(subscribed, fn %{module: mod} -> mod == &1 end))

    Enum.each(
      not_subscribed,
      &IO.warn(
        "You are using the module #{&1} in #{env.module}, but you have not called #{&1}.subscribe(Spec.t).  Make sure you subscribe to recieve messages in #{
          env.module
        }"
      )
    )
  end

  def make_callback_module(host_module, state_type, topic) do
    IO.inspect(binding())

    callbacks =
      for {event, spec} <- topic.events do
        function = String.to_atom("handle_#{topic.topic}_#{event}")

        quote do
          @callback unquote(function)(unquote(spec), unquote(state_type)) :: unquote(state_type)
        end
      end

    behviour_module_name = make_behaviour_module_name(topic)

    expanded_name = Module.concat(host_module, behviour_module_name)

    quote do
      defmodule unquote(expanded_name) do
        unquote(callbacks)
      end

      @behaviour unquote(expanded_name)
    end
  end

  defp make_behaviour_module_name(%{module: module}) do
    module
    |> Module.split()
    |> List.last()
    |> Kernel.<>("Behaviour")
    |> String.to_atom()
  end

  defp alias_state_type({atom, ctx, args}, module) when is_atom(atom) do
    namespace =
      module
      |> Module.split()
      |> Enum.map(&String.to_existing_atom(&1))

    {{:., ctx, [{:__aliases__, ctx, namespace}, atom]}, ctx, args || []}
  end

  defp alias_state_type(t, _), do: t
end
