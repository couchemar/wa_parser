;; PENDING control flow: countdown loop — block exit + loop back edge.
(module
  (func (export "sum_to") (param $n i32) (result i32)
    (local $acc i32)
    (block $exit
      (loop $l
        (br_if $exit (i32.le_s (local.get $n) (i32.const 0)))
        (local.set $acc (i32.add (local.get $acc) (local.get $n)))
        (local.set $n (i32.sub (local.get $n) (i32.const 1)))
        (br $l)))
    local.get $acc))
