defmodule WaParser.LEB128 do
  @moduledoc """
  LEB128 variable-length integer encoding/decoding.

  Thin Elixir wrapper over the Erlang core (`:wa_parser_leb128`).
  """

  defdelegate encode_unsigned(int), to: :wa_parser_leb128
  defdelegate decode_unsigned(bin), to: :wa_parser_leb128
  defdelegate encode_signed(int), to: :wa_parser_leb128
  defdelegate decode_signed(bin), to: :wa_parser_leb128
end
