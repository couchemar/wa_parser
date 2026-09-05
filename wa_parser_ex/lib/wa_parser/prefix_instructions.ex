defmodule WaParser.PrefixInstrs do
  @moduledoc """
  Sub-opcode tables for prefixed instructions (0xFB GC, 0xFD SIMD,
  0xFE threads/atomics).

  Thin Elixir wrapper over the Erlang core (`:wa_parser_instr`).
  """

  alias WaParser.ParseError

  def simd(sub), do: call(fn -> :wa_parser_instr.simd(sub) end)
  def fe(sub), do: call(fn -> :wa_parser_instr.fe(sub) end)
  def gc(sub), do: call(fn -> :wa_parser_instr.gc(sub) end)

  # The Erlang core signals parse failures with
  # `erlang:error({parse_error, reason, detail})`; convert to %ParseError{}.
  defp call(fun) do
    fun.()
  rescue
    e in ErlangError ->
      case e.original do
        {:parse_error, reason, detail} -> raise ParseError, reason: reason, detail: detail
        _ -> reraise e, __STACKTRACE__
      end
  end
end
