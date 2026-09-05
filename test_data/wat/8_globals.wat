;; Exercises global section parsing with intentional values instead of linker noise.
;; No global.get yet - the parser has no 0x23 clause, so funcs must not read globals.
(module
  (global $answer i32 (i32.const 42))
  (global $counter (mut i32) (i32.const -7)))
