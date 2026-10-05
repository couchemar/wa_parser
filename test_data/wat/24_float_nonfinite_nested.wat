;; The shape that actually broke: a non-finite constant buried in the middle of
;; a nested function body, with live instructions on both sides of it.
;;
;; The parser threads a body through an accumulator, so a decode failure at the
;; constant corrupts everything after it rather than just that one instruction.
;; That is why the javy QuickJS module aborted as a whole: its NaN sat inside
;; nested `if`/`block`, and 1467 other function bodies followed it.
(module
  (func (export "scale") (param $x f64) (result f64)
    (local $acc f64)

    (local.set $acc (f64.const 1.5))

    (if (f64.eq (local.get $x) (f64.const 0))
      (then
        (local.set $acc (f64.const inf))
        (drop
          (block (result f64)
            (br 0 (f64.mul (local.get $acc) (f64.const nan)))))))

    (f64.add (local.get $acc) (f64.const -inf))))