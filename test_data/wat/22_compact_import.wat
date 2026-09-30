;; Compact import section proposal (marker 0x7F): two function imports that
;; share the module name "env". Compiled with --enable-compact-imports so
;; wat2wasm deduplicates the shared module name into a single compact entry.
;; The parser must flatten it back into two individual imports.
(module
  (import "env" "a" (func $a (param i32) (result i32)))
  (import "env" "b" (func $b (param i32 i32) (result i32)))

  (func (export "run") (param i32) (result i32)
    (call $a (local.get 0))))
