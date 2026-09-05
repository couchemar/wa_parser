;; Exercises tag section, throw, try_table with catch and catch_all.
(module
  (tag $e (param i32))

  (func $boom
    (throw $e (i32.const 7)))

  (func (export "typed") (result i32)
    (block $h (result i32)
      (try_table (result i32) (catch $e $h)
        (call $boom)
        (i32.const 111))))

  (func (export "any") (result i32)
    (block $h
      (try_table (catch_all $h)
        (call $boom)))
    (i32.const 999)))
