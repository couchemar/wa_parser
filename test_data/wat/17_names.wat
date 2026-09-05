(module $m
  (global $answer i32 (i32.const 42))
  (memory $mem 1)

  (func $add_one (param $x i32) (result i32)
    (local $y i32)
    (local.set $y (i32.add (local.get $x) (i32.const 1)))
    local.get $y))
