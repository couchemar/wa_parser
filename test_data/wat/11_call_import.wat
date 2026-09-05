;; Exercises import section, call, return, nop, drop.
(module
  (import "env" "ext" (func $ext (param i32)))

  (func (export "run") (param i32)
    (call $ext (local.get 0))
    (nop)
    (if
      (i32.eqz (local.get 0))
      (then (return)))
    (drop (i32.const 0))))
