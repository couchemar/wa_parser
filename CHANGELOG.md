# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This file covers both packages in the repo: the Erlang core `wa_parser` and the
Elixir wrapper `wa_parser_ex`, which are versioned together.

## [Unreleased]

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
[0.1.2]: https://github.com/couchemar/wa_parser
[0.1.1]: https://github.com/couchemar/wa_parser
