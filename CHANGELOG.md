# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This file covers both packages in the repo: the Erlang core `wa_parser` and the
Elixir wrapper `wa_parser_ex`, which are versioned together.

## [0.1.3] - 2026-10-05

### Fixed

- `f32.const`/`f64.const` with an infinite or NaN value aborted the parse.
  Matching a constant with a float-type binary (`<<V:64/little-float>>`) *fails*
  on non-finite bit patterns instead of yielding a value, so the constant fell
  into the truncation clause and the error reported the size of the entire
  remaining module — `f64 constant needs 8 bytes, got 968232` for a perfectly
  well-formed constant, with the parser desynced from that point on. Real
  toolchains emit these constantly: a single `f64.const` NaN in the javy
  QuickJS module aborted the whole 1.3 MB parse.

### Changed

- A non-finite float constant now decodes instead of raising: `+inf`/`-inf`
  atoms, and NaN as `{'nan', Payload}` / `{'-nan', Payload}`. Finite constants
  remain ordinary Erlang floats. `Payload` is the raw fraction field with the
  quiet bit included (`16#400000` for a bare f32 `nan`), which keeps the decode
  reversible and keeps signalling NaNs distinct from quiet ones — `wasm-validate`
  accepts both, so dropping that bit would lose information. Consumers matching
  on a constant must handle these four shapes.

## [0.1.2] - 2026-09-30

### Added

- Support for the WebAssembly compact import section proposal. The import
  section now decodes both compact encodings in addition to the standard form:
  marker `0x7F` (several imports sharing a module name) and marker `0x7E`
  (several imports sharing both a module name and an external type). Compact
  entries are flattened into the usual `{Module, Name, Desc}` list, so consumers
  see an identical import list regardless of encoding. This is what
  `wat2wasm --enable-compact-imports` (and `--enable-all`) emit for modules with
  multiple imports that share a module name.

### Fixed

- A module using a compact import section previously raised a
  `FunctionClauseError` in `importdesc/1` (the compact marker `0x7F`/`0x7E` is
  not a valid import-descriptor tag). Such modules now parse correctly.

### Changed

- Malformed import entries now raise structured `parse_error`s instead of a raw
  crash: `invalid_importdesc` for an unrecognized descriptor tag, and
  `malformed_compact_import` for a compact marker with a non-empty field name.

## [0.1.1]

- Previous released version.

[Unreleased]: https://github.com/couchemar/wa_parser
[0.1.3]: https://github.com/couchemar/wa_parser
[0.1.2]: https://github.com/couchemar/wa_parser
[0.1.1]: https://github.com/couchemar/wa_parser
