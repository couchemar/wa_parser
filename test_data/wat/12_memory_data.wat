;; Exercises table/elem/data/datacount/start sections, memory ops, globals.
(module
  (table 2 funcref)
  (memory (export "mem") 1 2)
  (global $g (mut i32) (i32.const 42))

  (elem (i32.const 0) $init)

  (data (i32.const 0) "\01\02\03")
  (data $passive "\ff")

  (func $init (export "init")
    (i32.store offset=8 (i32.const 0) (i32.const 7))
    (global.set $g (memory.size)))

  (start $init))
