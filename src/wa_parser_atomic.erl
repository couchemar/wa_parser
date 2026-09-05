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

f32(<<V:32/little-float, Rest/binary>>) ->
    {V, Rest};
f32(Bin) ->
    parse_error(truncated,
                bin_fmt("f32 constant needs 4 bytes, got ~B", [byte_size(Bin)])).

f64(<<V:64/little-float, Rest/binary>>) ->
    {V, Rest};
f64(Bin) ->
    parse_error(truncated,
                bin_fmt("f64 constant needs 8 bytes, got ~B", [byte_size(Bin)])).

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
