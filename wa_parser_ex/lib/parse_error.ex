defmodule WaParser.ParseError do
  @moduledoc """
  Raised when WASM input violates the binary format specification.

  `reason` is a stable atom for programmatic matching (`:bad_magic`,
  `:bad_version`, `:unknown_section`, `:unknown_opcode`, `:truncated`,
  `:non_canonical`, `:section_truncated`, `:unconsumed_section_bytes`,
  `:unknown_type`); `detail` carries human-readable context.
  """

  defexception [:reason, :detail]

  @impl true
  def message(%__MODULE__{reason: reason, detail: detail}) do
    "invalid WebAssembly binary (#{reason}): #{detail}"
  end
end
