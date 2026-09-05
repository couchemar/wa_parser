;; Mirrors wa_parser/test_data/5_int_factorial.c as a readable loop.
(module
  (func (export "factorial") (param $n i32) (result i32)
    (local $acc i32)
    (local $i i32)
    (local.set $acc (i32.const 1))
    (local.set $i (i32.const 1))
    (block $exit
      (loop $l
        (br_if $exit (i32.gt_s (local.get $i) (local.get $n)))
        (local.set $acc (i32.mul (local.get $acc) (local.get $i)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $l)))
    local.get $acc))
