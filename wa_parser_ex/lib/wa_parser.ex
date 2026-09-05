defmodule WaParser do
  @moduledoc """
  WebAssembly binary format parser.

  Thin Elixir wrapper over the Erlang core (`:wa_parser`). Erlang
  projects can consume `:wa_parser` directly; Elixir projects use this
  module.
  """

  alias WaParser.ParseError

  @doc """
  Parses a WASM binary into a lazy stream of parse events.

  Events: `{:magic, <<...>>}`, `{:version, <<...>>}`, `{:section_id, id}`,
  `{:section_type, type}`, `{:section_length, len}`, `{:section_body, body}`.
  """
  def stream(data) do
    :wa_parser.events(data)
  rescue
    e in ErlangError -> convert(e, __STACKTRACE__)
  end

  @doc """
  Parses the first top-level event, returning
  `{:ok, {event, rest, next}}` — the continuation form the stream is
  built on.
  """
  def parse(data) do
    :wa_parser.parse(data)
  rescue
    e in ErlangError -> convert(e, __STACKTRACE__)
  end

  # The Erlang core signals parse failures with
  # `erlang:error({parse_error, reason, detail})`; convert to %ParseError{}.
  defp convert(e, stack) do
    case e.original do
      {:parse_error, reason, detail} -> raise ParseError, reason: reason, detail: detail
      _ -> reraise e, stack
    end
  end
end
