defmodule Eflatbuffers.Schema do

  @referenced_types [
    :string,
    :byte,  :ubyte, :bool,
    :short, :ushort,
    :int,   :uint,  :float,
    :long,  :ulong, :double,
  ]

  def parse!(schema_str) do
    case parse(schema_str) do
      {:ok, schema} ->
        schema
      {:error, error} ->
        throw({:error, error})
    end
  end

  def parse(schema_str) when is_binary(schema_str) do
    tokens = lexer(schema_str)
    case :schema_parser.parse(tokens) do
      {:ok, data} ->
        {:ok, decorate(data)}
      error ->
        error
    end
  end

  def lexer(schema_str) do
    {:ok, tokens, _} =
      to_char_list(schema_str)
      |> :schema_lexer.string
    tokens
  end

  # this preprocesses the schema
  # in order to keep the read/write
  # code as simple as possible
  # correlate tables with names
  # and define defaults explicitly
  def decorate({entities, options}) do
    entities_decorated =
    Enum.reduce(
      entities,
      %{},
      # for a tables we transform
      # the types to explicitly signify
      # vectors, tables, and enums
      fn({key, {:table, fields}}, acc) ->
        Map.put(
          acc,
          key,
          {
            :table,
            %{
              fields:  decorate_fields(fields, entities),
              indices: indices(fields, entities)
            }
          }
        )
        # for enums we change the list of options
        # into a map for faster lookup when
        # writing and reading
        ({key, {{:enum, type}, fields}}, acc) ->
          hash = Enum.reduce(
            Enum.with_index(fields),
            %{},
            fn({field, index}, hash_acc) ->
              Map.put(hash_acc, field, index) |> Map.put(index, field)
            end
          )
          Map.put(acc, key, {:enum, %{ type: {type, %{ default: 0 }}, members: hash }})
        ({key, {:union, fields}}, acc) ->
          hash = Enum.reduce(
            Enum.with_index(fields),
            %{},
            fn({field, index}, hash_acc) ->
              Map.put(hash_acc, field, index) |> Map.put(index, field)
            end
          )
          Map.put(acc, key, {:union, %{ members: hash }})
      end
    )
    {entities_decorated, options}
  end

  def decorate_fields(fields, entities) do
   Enum.map(fields, fn({field_name, field_value}) -> {field_name, decorate_field(field_value, entities)} end)
  end

  def indices(fields, entities) do
    Enum.reduce(
    fields,
    {0, %{}},
    fn({field_name, field_value}, {index, acc}) ->
      {index_offset, type} = index_offset_and_type(field_value, entities)
      { index + index_offset, Map.put(acc, field_name, {index, type})} end
    )
    |> elem(1)
  end


  def index_offset_and_type(field_value, entities) do
    case is_referenced?(field_value) do
      true ->
        case Map.get(entities, field_value) do
          {:union, _} ->
            {2, decorate_field(field_value, entities)}
          _ ->
            {1, decorate_field(field_value, entities)}
        end
      false ->
        {1, decorate_field(field_value, entities)}
    end
  end


  def decorate_field({:vector, type}, entities) do
    {:vector, %{ type: decorate_field(type, entities) }}
  end

  def decorate_field(field_value, entities) do
    case is_referenced?(field_value) do
      true ->
        decorate_referenced_field(field_value, entities)
      false ->
        decorate_field(field_value)
    end
  end

  def decorate_referenced_field(field_value, entities) do
    case Map.get(entities, field_value) do
      nil ->
        throw({:error, {:entity_not_found, field_value}})
      {:table, _} ->
        {:table, %{ name: field_value }}
      {{:enum, _}, _} ->
        {:enum,  %{ name: field_value }}
      {:union, _} ->
        {:union, %{ name: field_value }}
    end
  end

  def decorate_field({type, default}) do
    {type, %{ default: default} }
  end
  def decorate_field(:bool) do
    {:bool, %{ default: false }}
  end
  def decorate_field(:string) do
    {:string, %{}}
  end
  def decorate_field(type) do
    {type, %{ default: 0 }}
  end

  def is_referenced?({type, _default}) do
    is_referenced?(type)
  end
  def is_referenced?(type) do
    not Enum.member?(@referenced_types, type)
  end
end
