# WaParserEx

Idiomatic Elixir wrapper over [`wa_parser`](https://hex.pm/packages/wa_parser),
a WebAssembly binary format parser. The parsing core is Erlang
(`:wa_parser`); this package adds an Elixir-friendly API and a proper
exception type.

## Installation

```elixir
def deps do
  [
    {:wa_parser_ex, "~> 0.1"}
  ]
end
```

This pulls in the Erlang `wa_parser` core as a transitive dependency.

## Usage

```elixir
"module.wasm"
|> File.read!()
|> WaParser.stream()
|> Enum.to_list()
```

`WaParser.stream/1` returns a lazy stream of parse events; `WaParser.parse/1`
returns the single-step continuation form. Malformed input raises
`WaParser.ParseError`, whose `reason` field is a stable atom for
programmatic matching (`:bad_magic`, `:truncated`, `:unknown_opcode`,
`:non_canonical`, …).

Additional helpers wrap the core's utility modules: `WaParser.LEB128`
(variable-length integer encode/decode) and `WaParser.PrefixInstrs`
(prefixed-instruction sub-opcode tables).

## License

Released into the public domain under the [Unlicense](UNLICENSE).
