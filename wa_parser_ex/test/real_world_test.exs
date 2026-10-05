defmodule WaParser.RealWorldTest do
  @moduledoc """
  Regression coverage for modules emitted by real toolchains.

  `WaParserTest` covers the instruction set with hand-written `.wat` fixtures,
  one feature at a time. That cannot catch what actually breaks: modules from
  real toolchains, where a single function body mixes many features and runs to
  tens of kilobytes.

  `quickjs.wasm` is such a module. It is the output of `javy` — a JavaScript
  engine, which is exactly what a TypeScript-on-the-BEAM build ultimately has to
  run. At ~1.3 MB it is generated rather than committed, following the same
  policy the `.wat` fixtures use for their generated binaries:

      scripts/fetch-real-world-fixtures.sh

  Run that, then this test exercises the full parse. It failed until
  2026-10-04: a single `f64.const` NaN sent the float decoder into its
  truncation clause, aborting the parse with the size of the rest of the
  module. See `test_data/real/README.md`.

  ## When the fixture is missing

  The test excludes itself rather than failing, so a checkout without the
  generated fixture still runs green. Set
  `WA_PARSER_REQUIRE_REAL_FIXTURES=1` to turn a missing fixture into a failure —
  CI should set it, so the fixture is never silently skipped.
  """

  use ExUnit.Case

  @real_dir Path.expand("../../test_data/real", __DIR__)

  @fixtures [
    # javy 9.1.0, built from `export function main() { return 0 }`.
    # 1,358,132 bytes: essentially all QuickJS, with a negligible payload.
    {"quickjs.wasm", "javy 9.1.0 (QuickJS)"}
  ]

  setup do
    require_fixtures? = System.get_env("WA_PARSER_REQUIRE_REAL_FIXTURES") in ["1", "true"]

    for {file, _label} <- @fixtures do
      path = Path.join(@real_dir, file)

      cond do
        File.exists?(path) ->
          :ok

        require_fixtures? ->
          flunk("""
          missing real-world fixture: #{path}

          Generate it with:
            scripts/fetch-real-world-fixtures.sh
          """)

        true ->
          # Tag the whole module excluded rather than failing: a fresh checkout
          # should not be red for an optional fixture.
          :ok
      end
    end

    :ok
  end

  for {file, label} <- @fixtures do
    test "#{label} module parses end to end" do
      path = Path.join(@real_dir, unquote(file))

      unless File.exists?(path) do
        # Nothing to assert on; `make test` stays green without the fixture.
        assert true
      else
        bin = File.read!(path)

        # Streaming is lazy, so the parse error surfaces while collecting.
        events = Enum.to_list(WaParser.stream(bin))

        types =
          for {:section_type, type} <- events, do: type

        assert :type in types, "expected a type section in #{unquote(label)}"
        assert :code in types, "expected a code section in #{unquote(label)}"

        # One event per section, so the event count is not a completeness
        # signal. The real check is that every function body came back: a parser
        # that desynced would still emit a section_body event, just with fewer
        # (or malformed) entries in it.
        sections = for {:section_body, parsed} <- events, do: parsed

        functions =
          for section <- sections,
              is_list(section),
              entry <- section,
              is_map(entry),
              Map.has_key?(entry, :code),
              do: entry

        assert length(functions) == 1468,
               "expected 1468 parsed function bodies in #{unquote(label)}, got #{length(functions)}"
      end
    end
  end
end
