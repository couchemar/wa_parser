;; Exercises 0xFD SIMD: load/store, splat, lanes, shuffle, arithmetic.
(module
  (memory 1)

  (func (export "vops") (param $x i32) (result i32)
    (local $v v128)
    i32.const 0
    v128.load offset=2
    local.set $v
    local.get $v
    local.get $x
    i32x4.splat
    i32x4.add
    local.set $v
    local.get $v
    local.get $v
    i8x16.shuffle 0 15 1 14 2 13 3 12 4 11 5 10 6 9 7 8
    drop
    local.get $v
    f64x2.abs
    drop
    local.get $v
    v128.any_true
    drop
    local.get $v
    i32x4.extract_lane 0))
