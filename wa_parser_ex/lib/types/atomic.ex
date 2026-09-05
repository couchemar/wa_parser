defmodule WaParser.Types.Atomic do
  @moduledoc false

  alias WaParser.ParseError

  # Unsigned LEB128
  def u32(binary), do: call(fn -> :wa_parser_atomic.u32(binary) end)
  def u64(binary), do: call(fn -> :wa_parser_atomic.u64(binary) end)

  # Signed LEB128 (s33 is the blocktype/heaptype encoding)
  def i32(binary), do: call(fn -> :wa_parser_atomic.i32(binary) end)
  def i64(binary), do: call(fn -> :wa_parser_atomic.i64(binary) end)
  def s33(binary), do: call(fn -> :wa_parser_atomic.s33(binary) end)

  def f32(binary), do: call(fn -> :wa_parser_atomic.f32(binary) end)
  def f64(binary), do: call(fn -> :wa_parser_atomic.f64(binary) end)

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
