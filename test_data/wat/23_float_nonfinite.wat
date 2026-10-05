;; Non-finite float constants.
;;
;; An Erlang float cannot represent infinity or NaN, so these decode to `+inf`,
;; `-inf`, or `{'nan', Payload}` / `{'-nan', Payload}` instead of raising. Real
;; toolchains emit them constantly: javy's QuickJS module contains a single
;; `f64.const` NaN that was enough to abort the whole parse before this was
;; handled. A bare `nan' carries payload 16#400000 (the quiet bit is part of the
;; payload, not implied) and `nan:0x1234' carries 16#1234, so the whole fraction
;; field round-trips.
(module
  (func (export "f32_nonfinite")
    (drop (f32.const 1.5))
    (drop (f32.const inf))
    (drop (f32.const -inf))
    (drop (f32.const nan))
    (drop (f32.const -nan:0x1234)))

  (func (export "f64_nonfinite")
    (drop (f64.const 1.5))
    (drop (f64.const inf))
    (drop (f64.const -inf))
    (drop (f64.const nan))))