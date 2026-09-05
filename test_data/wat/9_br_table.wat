;; Exercises br_table: three nested blocks, index selects exit depth.
(module
  (func (export "pick") (param $i i32) (result i32)
    (local $r i32)
    (local.set $r (i32.const 30))
    (block $outer
      (block $mid
        (block $inner
          local.get $i
          br_table 0 1 2)
        (local.set $r (i32.const 10))
        (br 1))
      (local.set $r (i32.const 20)))
    local.get $r))
