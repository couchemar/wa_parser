-module(wa_parser_atomic).

%% Atomic value decoders: LEB128 integers with width/canonicality
%% enforcement, and little-endian IEEE 754 floats.

-export([u32/1, u64/1, i32/1, i64/1, s33/1, f32/1, f64/1]).

%% Unsigned LEB128
u32(Bin) -> leb(Bin, 5, 32, unsigned).
u64(Bin) -> leb(Bin, 10, 64, unsigned).

%% Signed LEB128 (s33 is the blocktype/heaptype encoding)
i32(Bin) -> leb(Bin, 5, 32, signed).
i64(Bin) -> leb(Bin, 10, 64, signed).
s33(Bin) -> leb(Bin, 5, 33, signed).

%% Erlang floats cannot represent infinity or NaN, and a `<<V:N/little-float>>'
%% match FAILS on those bit patterns rather than yielding a value. Matching on
%% the float type therefore sent every `f32.const inf/nan' and `f64.const
%% inf/nan' into the error clause below, which then reported the size of the
%% entire remaining module — a bogus "f64 constant needs 8 bytes, got 968232"
%% for a perfectly well-formed constant, with the parser desynced from that
%% point on. Real toolchains emit these constantly: one `f64.const' NaN in the
%% javy QuickJS module was enough to abort a 1.3 MB parse.
%%
%% So match the raw bits instead. An all-ones exponent is an infinity when the
%% fraction is zero and a NaN otherwise; the sign bit is independent of both:
%%
%%     f32.const  1.5         ->  1.5              (an ordinary Erlang float)
%%     f32.const  inf         ->  '+inf'
%%     f32.const -inf         ->  '-inf'
%%     f32.const  nan:0x1234  ->  {'nan', 16#401234}
%%     f32.const -nan:0x1234  ->  {'-nan', 16#401234}
%%
%% Payload is the whole fraction field, quiet bit included, so the decode is
%% lossless and reversible: sign, payload and the all-ones exponent rebuild the
%% exact 32/64-bit pattern. Keeping the quiet bit is not cosmetic —
%% wasm-validate accepts signalling NaNs such as 0x7F800001, and dropping that
%% bit would conflate them with the quiet NaN carrying the same low payload
%% (0x7FC00001). A bare `nan' therefore carries payload 16#400000 (f32) or
%% 16#8000000000000 (f64) — the quiet bit sits in the payload rather than being
%% implied — while `nan:0x1234' surfaces as 16#1234.

f32(<<Bits:32/little-unsigned, Rest/binary>>) ->
    {f32_value(Bits), Rest};
f32(Bin) ->
    parse_error(truncated,
                bin_fmt("f32 constant needs 4 bytes, got ~B", [byte_size(Bin)])).

f64(<<Bits:64/little-unsigned, Rest/binary>>) ->
    {f64_value(Bits), Rest};
f64(Bin) ->
    parse_error(truncated,
                bin_fmt("f64 constant needs 8 bytes, got ~B", [byte_size(Bin)])).

%% Only the sign bit and the fraction-field width differ between the two sizes.

f32_value(Bits) when (Bits band 16#7F800000) =:= 16#7F800000 ->
    non_finite(Bits, 16#80000000, 16#7FFFFF);
f32_value(Bits) ->
    <<V:32/little-float>> = <<Bits:32/little>>,
    V.

f64_value(Bits) when (Bits band 16#7FF0000000000000) =:= 16#7FF0000000000000 ->
    non_finite(Bits, 16#8000000000000000, 16#FFFFFFFFFFFFF);
f64_value(Bits) ->
    <<V:64/little-float>> = <<Bits:64/little>>,
    V.

non_finite(Bits, SignBit, FractionMask) ->
    Negative = (Bits band SignBit) =/= 0,
    case Bits band FractionMask of
        0 when Negative ->
            '-inf';
        0 ->
            '+inf';
        Payload when Negative ->
            {'-nan', Payload};
        Payload ->
            {'nan', Payload}
    end.

%% Takes at most MaxBytes of LEB128 wire bytes, enforces the `Bits`
%% width limit, then hands the original wire bytes to the byte-oriented
%% decoders and wraps the result to the declared width (spec-legal
%% redundant padding in the terminal byte must not leak into the value).
leb(Bin, MaxBytes, Bits, Kind) ->
    {WireRev, TerminalPayload, Rest} = leb_wire(Bin, MaxBytes, []),
    Wire = iolist_to_binary(lists:reverse(WireRev)),
    check_width(length(WireRev), TerminalPayload, Bits, Kind),

    Mask = (1 bsl Bits) - 1,

    Value =
        case Kind of
            unsigned ->
                wa_parser_leb128:decode_unsigned(Wire) band Mask;
            signed ->
                W = wa_parser_leb128:decode_signed(Wire) band Mask,
                case W >= (1 bsl (Bits - 1)) of
                    true -> W - (1 bsl Bits);
                    false -> W
                end
        end,

    {Value, Rest}.

%% Prepends each wire byte, so the accumulator ends up terminal-first.
leb_wire(<<>>, _MaxBytes, _Acc) ->
    parse_error(truncated, <<"unterminated LEB128 sequence">>);
leb_wire(<<Byte, Rest/binary>>, MaxBytes, Acc) ->
    Cont = Byte bsr 7,
    Payload = Byte band 16#7F,
    Acc2 = [Byte | Acc],

    case Cont of
        1 ->
            case length(Acc2) > MaxBytes of
                true ->
                    parse_error(non_canonical,
                                bin_fmt("LEB128 exceeds ~B byte(s)", [MaxBytes]));
                false ->
                    leb_wire(Rest, MaxBytes, Acc2)
            end;
        0 ->
            {Acc2, Payload, Rest}
    end.

check_width(N, TerminalPayload, Bits, Kind) ->
    case N > ceil(Bits / 7) of
        true ->
            parse_error(non_canonical,
                        bin_fmt("LEB128 exceeds ~B-bit width", [Bits]));
        false ->
            ok
    end,
    Rem = min(Bits - 7 * (N - 1), 7),
    check_terminal_bits(TerminalPayload, Rem, Kind, Bits).

%% Unused high bits of the terminal byte's payload must be zero for
%% unsigned, and must replicate the sign bit for signed encodings.
%% Encodings that stay within the width limit but pad redundantly are
%% legal per spec and pass through.
check_terminal_bits(G, Rem, unsigned, Bits) ->
    case G bsr Rem of
        0 -> ok;
        _ ->
            parse_error(non_canonical,
                        bin_fmt("unsigned LEB128 has set bits beyond its ~B-bit width",
                                [Bits]))
    end;
check_terminal_bits(G, Rem, signed, _Bits) ->
    Pad = 7 - Rem,
    case Pad > 0 of
        false ->
            ok;
        true ->
            Hi = G bsr Rem,
            Sign = (G bsr (Rem - 1)) band 1,
            Expected =
                case Sign of
                    1 -> (1 bsl Pad) - 1;
                    0 -> 0
                end,
            case Hi =:= Expected of
                true -> ok;
                false ->
                    parse_error(non_canonical,
                                <<"signed LEB128 padding does not match sign bit">>)
            end
    end.

bin_fmt(Fmt, Args) -> iolist_to_binary(io_lib:format(Fmt, Args)).

parse_error(Reason, Detail) ->
    erlang:error({parse_error, Reason, Detail}).
