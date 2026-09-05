;; Exercises FC bulk-memory and table opcodes; passive data forces datacount.
(module
  (type $ret (func (result i32)))
  (table 4 funcref)
  (memory 1)

  (data "\01\02")
  (elem func $f)

  (func $f (result i32) (i32.const 7))

  (func (export "run") (result i32)
    (memory.init 0 (i32.const 0) (i32.const 0) (i32.const 2))
    (data.drop 0)
    (memory.fill (i32.const 0) (i32.const 65) (i32.const 2))
    (memory.copy (i32.const 0) (i32.const 1) (i32.const 1))
    (table.init 0 0 (i32.const 0) (i32.const 0) (i32.const 1))
    (table.size 0)
    (drop)
    (call_indirect (type $ret) (i32.const 0))))
