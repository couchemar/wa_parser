# Real-world fixtures

Modules emitted by real toolchains, used by
[`wa_parser_ex/test/real_world_test.exs`](../../wa_parser_ex/test/real_world_test.exs).

Unlike `../wat`, which holds hand-written instruction-level fixtures built by
CMake/Ninja, these come from real compilers. They are far too large to commit,
so they are generated and gitignored, like the `.wasm` outputs in `../wat`.

## `quickjs.wasm`

| | |
|---|---|
| Producer | [javy](https://github.com/bytecodealliance/javy) 9.1.0 |
| Source | `export function main() { return 0 }` |
| Size | 1,358,132 bytes |
| Contents | A complete QuickJS interpreter; the JS payload is negligible |

This is the module a JavaScript-on-the-BEAM build ultimately has to run, so it
is the one that matters. QuickJS emits very large function bodies — the first
is 51,336 bytes — which is unlike anything in `../wat`.

## Generating

```bash
scripts/fetch-real-world-fixtures.sh
```

Needs network access on first run; the `javy` binary is cached in `.cache/`.

## Running the test

```bash
make test                                    # skips the test if not generated
WA_PARSER_REQUIRE_REAL_FIXTURES=1 make test  # fails if not generated
```

CI should set `WA_PARSER_REQUIRE_REAL_FIXTURES=1` and run the fetch script, so
the fixture is never silently skipped.

## Previously failing, now fixed

Until 2026-10-04 this test failed with:

```
{parse_error, truncated, <<"f64 constant needs 8 bytes, got 968232">>}
```

`wasm-validate` accepts the same file, so the module was valid and the parser
was wrong. The cause sat in `wa_parser_atomic:f32/1` and `f64/1`: matching a
constant with `<<V:64/little-float>>` **fails** on non-finite bit patterns
instead of yielding a value, so a well-formed `inf`/`nan` constant fell into
the truncation clause, which reported the size of the entire remaining module.

This module carries 40 float constants, exactly one of which is non-finite — a
single `f64.const` NaN (`0x7FF8000000000000`) aborted the whole 1.3 MB parse.
The other 39 are finite and decode as ordinary Erlang floats; the NaN now
decodes to `{'nan', 16#8000000000000}`, since no Erlang float can hold it.
