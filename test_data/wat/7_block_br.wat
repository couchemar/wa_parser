;; PENDING control flow: block guard with two successors, MVP-only instructions.
(module
  (func (export "nonneg_or_zero") (param $v i32) (result i32)
    (local $r i32)
    (local.set $r (local.get $v))
    (block $skip
      (br_if $skip (i32.ge_s (local.get $v) (i32.const 0)))
      (local.set $r (i32.const 0)))
    local.get $r))
