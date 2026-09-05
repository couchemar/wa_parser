;; Mirrors test_data/2_int_arithm.c
(module
  (func (export "inc") (param i32) (result i32)
    local.get 0
    i32.const 1
    i32.add)

  (func (export "dec") (param i32) (result i32)
    local.get 0
    i32.const 1
    i32.sub)

  (func (export "tri") (param i32) (result i32)
    local.get 0
    i32.const 3
    i32.mul)

  (func (export "third") (param i32) (result i32)
    local.get 0
    i32.const 3
    i32.div_s))
