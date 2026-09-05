# wa_parser

A WebAssembly binary format parser for the Erlang ecosystem, written in
Erlang. It parses a `.wasm` binary into a flat sequence of parse events —
no dependencies beyond `kernel` and `stdlib`.

This is the Erlang package. Elixir projects can depend on it directly, or
use the companion [`wa_parser_ex`](https://hex.pm/packages/wa_parser_ex)
package for an idiomatic Elixir API.

## Installation (rebar3)

```erlang
%% rebar.config
{deps, [{wa_parser, "~> 0.1"}]}.
```

## Usage

```erlang
{ok, Bin} = file:read_file("module.wasm"),
Events = wa_parser:events(Bin).
```

`events/1` returns the full list of parse events. Each event is one of:

- `{magic, Bin}` / `{version, Bin}` — the 8-byte header
- `{section_id, Id}` / `{section_type, Type}` / `{section_length, Len}`
- `{section_body, Body}` — the decoded section contents

For incremental parsing, `parse/1` returns
`{ok, {Event, Rest, NextFun}}` — the continuation the event list is built
on.

Malformed input raises `erlang:error({parse_error, Reason, DetailBin})`,
where `Reason` is a stable atom for programmatic matching (`bad_magic`,
`bad_version`, `unknown_section`, `unknown_opcode`, `truncated`,
`non_canonical`, `section_truncated`, `unconsumed_section_bytes`,
`unknown_type`) and `DetailBin` is human-readable context.

## Supported features

Parses all standard WASM sections (type, import, function, table, memory,
global, export, start, element, code, data, data_count, tag, custom
including the name subsection) and the full instruction set: control flow,
locals/globals, direct/indirect/tail calls, i32/i64/f32/f64 numerics,
memory load/store, reference types, SIMD (0xFD), GC (0xFB),
atomics/threads (0xFE), bulk memory (0xFC), and exception handling
(`try_table`, `throw`, `throw_ref`).

## License

Released into the public domain under the [Unlicense](UNLICENSE).
