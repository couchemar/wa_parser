;; Mirrors test_data/4_int_comp.c
(module
  (func (export "eq") (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.eq)

  (func (export "ne") (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.ne)

  (func (export "lt") (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.lt_s)

  (func (export "gt") (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.gt_s)

  (func (export "le") (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.le_s)

  (func (export "ge") (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.ge_s))
