;; Exercises 0xFE threads/atomics with shared memory.
(module
  (memory 1 1 shared)

  (func (export "wait32") (result i32)
    (memory.atomic.wait32 (i32.const 0) (i32.const 0) (i64.const -1)))

  (func (export "load") (result i32)
    (i32.atomic.load (i32.const 0)))

  (func (export "rmw") (result i32)
    (i32.atomic.rmw.add (i32.const 0) (i32.const 1))))
