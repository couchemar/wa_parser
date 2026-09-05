;; Exercises ref.null / ref.func / ref.is_null and table.set / grow / fill.
(module
  (type $ret (func (result i32)))
  (table 2 funcref)
  (memory 1)

  (elem declare func $f)

  (func $f (result i32) (i32.const 7))

  (func (export "run") (result i32)
    (table.set 0 (i32.const 0) (ref.func $f))
    (drop (table.grow 0 (ref.null func) (i32.const 1)))
    (if (ref.is_null (ref.null func))
      (then nop))
    (table.fill 0 (i32.const 1) (ref.null func) (i32.const 1))
    (call_indirect (type $ret) (i32.const 0))))
