(module
  (type $ret (func (result i32)))
  (table 1 funcref)
  (func $g (result i32) (i32.const 1))

  (func (export "direct") (result i32)
    (return_call $g))

  (func (export "indirect") (result i32)
    (return_call_indirect (type $ret) (i32.const 0))))
