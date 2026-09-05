;; Exercises non-i32 consts, conversions, sign-extension, saturating truncation.
(module
  (func (export "mix") (param $x i32) (result f64)
    (f64.add
      (f64.const 1.5)
      (f64.convert_i32_u (i32.extend8_s (local.get $x)))))

  (func (export "sat") (param $p f32) (result i32)
    (i32.trunc_sat_f32_s (local.get $p))))
