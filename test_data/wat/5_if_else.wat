;; PENDING control flow: real if/else — what wasm-opt erases from 3_int_cond.
(module
  (func (export "max") (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.gt_s
    if (result i32)
      local.get 0
    else
      local.get 1
    end))
