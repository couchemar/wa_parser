;; Exercises blocktype as a signed-LEB128 type index (multi-value block).
(module
  (type $pair (func (result i32 i32)))

  (func (export "two") (result i32 i32)
    (block (type $pair)
      (i32.const 1)
      (i32.const 2))))
