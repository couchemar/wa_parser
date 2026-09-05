-module(wa_parser_leb128).

%% LEB128 variable-length integer encoding/decoding (WASM binary format).

-export([encode_unsigned/1, decode_unsigned/1, encode_signed/1, decode_signed/1]).

%% -- Encoding --------------------------------------------------------------

encode_unsigned(0) ->
    <<16#00>>;
encode_unsigned(Int) when Int > 0 ->
    list_to_binary(do_encode_unsigned(Int)).

do_encode_unsigned(Int) when Int < 16#80 ->
    [Int];
do_encode_unsigned(Int) ->
    [16#80 bor (Int band 16#7F) | do_encode_unsigned(Int bsr 7)].

encode_signed(0) ->
    <<16#00>>;
encode_signed(Int) ->
    list_to_binary(do_encode_signed(Int)).

%% Terminal byte rule: after shifting, a non-negative value must have no
%% sign bit set in the payload, and a negative value must keep it set.
do_encode_signed(Int) ->
    B = Int band 16#7F,
    Rest = Int bsr 7,
    Done = (Rest =:= 0 andalso (B band 16#40) =:= 0) orelse
           (Rest =:= -1 andalso (B band 16#40) =/= 0),
    case Done of
        true ->
            [B];
        false ->
            [16#80 bor B | do_encode_signed(Rest)]
    end.

%% -- Decoding --------------------------------------------------------------

decode_unsigned(Bin) ->
    decode_unsigned(Bin, <<>>).

decode_unsigned(<<0:1, Byte:7>>, Acc) ->
    bits_to_int(<<Byte:7, Acc/bits>>, unsigned);
decode_unsigned(<<1:1, Byte:7, Rest/binary>>, Acc) ->
    decode_unsigned(Rest, <<Byte:7, Acc/bits>>).

decode_signed(Bin) ->
    decode_signed(Bin, <<>>).

decode_signed(<<0:1, Byte:7>>, Acc) ->
    bits_to_int(<<Byte:7, Acc/bits>>, signed);
decode_signed(<<1:1, Byte:7, Rest/binary>>, Acc) ->
    decode_signed(Rest, <<Byte:7, Acc/bits>>).

bits_to_int(Bits, Signedness) ->
    Size = bit_size(Bits),
    Int =
        case Signedness of
            unsigned ->
                <<V:Size/unsigned-integer>> = Bits,
                V;
            signed ->
                <<V:Size/signed-integer>> = Bits,
                V
        end,
    Int.
