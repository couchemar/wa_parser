;; Mirrors test_data/3_int_cond.c as lowered by wasm-opt:
;; if/else collapsed to select. The unlowered if/else form lives in 5_if_else.wat.
(module
  (func (export "ge_select") (param i32 i32) (result i32)
    local.get 0
    local.get 1
    local.get 0
    local.get 1
    i32.ge_s
    select))
