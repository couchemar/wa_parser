-module(wa_parser).

-moduledoc """
WebAssembly binary format parser — event based.

Parses a `.wasm` binary into a flat sequence of parse events. Use it
directly from Erlang:

```erlang
Events = wa_parser:events(Binary).
```

Each event is one of `{magic, Bin}`, `{version, Bin}`, `{section_id, Id}`,
`{section_type, Type}`, `{section_length, Len}`, `{section_body, Body}`.
Malformed input raises `erlang:error({parse_error, Reason, DetailBin})`,
where `Reason` is a stable atom (e.g. `bad_magic`, `truncated`,
`unknown_opcode`, `non_canonical`) suitable for programmatic matching.

Elixir projects can use the `wa_parser_ex` package for an idiomatic
wrapper (`WaParser.stream/1` plus a `%WaParser.ParseError{}` exception).
""".

%% Parse failures are raised as erlang:error({parse_error, Reason, DetailBin}).

-export([events/1, parse/1]).

-doc """
Parses a WASM binary into the full list of parse events.

Raises `erlang:error({parse_error, Reason, Detail})` on malformed input.
""".

%% ============================================================================
%% Event enumeration (eager equivalent of the Elixir Stream.resource)
%% ============================================================================

%% Halt only at top-level boundaries: an empty remainder handed to a
%% section-body continuation means truncation and must still be parsed
%% so it can raise.
events(Data) ->
    events(Data, fun parse/1).

events(<<>>, Fun) ->
    TopLevel = Fun =:= fun parse/1 orelse Fun =:= fun parse_section/1,

    case TopLevel of
        true ->
            [];
        false ->
            %% Empty remainder with a continuation still pending: run it
            %% so truncation surfaces instead of halting silently.
                case Fun(<<>>) of
                    {ok, {Result, <<>>, Next}} when is_list(Result) ->
                        Result ++ events(<<>>, Next);
                    {ok, {Result, <<>>, Next}} ->
                        [Result | events(<<>>, Next)];
                    _ ->
                        parse_error(truncated, <<"unexpected end of module">>)
                end
            end;
events(Data, Parser) ->
    case Parser(Data) of
        {ok, {Result, Rest, Next}} when is_list(Result) ->
            Result ++ events(Rest, Next);
        {ok, {Result, Rest, Next}} ->
            [Result | events(Rest, Next)]
    end.

%% ============================================================================
%% Top-level: magic, version, sections
%% ============================================================================

parse(<<0, 97, 115, 109, Rest/binary>>) ->
    {ok, {{magic, <<0, 97, 115, 109>>}, Rest, fun parse_version/1}};
parse(<<_:4/binary>> = Magic) ->
    parse_error(bad_magic,
                bin_fmt("expected <<0, 97, 115, 109>>, got ~w", [Magic]));
parse(Binary) ->
    parse_error(bad_magic,
                bin_fmt("input is ~B byte(s), need at least 4 for the magic header",
                        [byte_size(Binary)])).

parse_version(<<1, 0, 0, 0, Rest/binary>>) ->
    {ok, {{version, <<1, 0, 0, 0>>}, Rest, fun parse_section/1}};
parse_version(<<_:4/binary>> = Version) ->
    parse_error(bad_version,
                bin_fmt("expected version 1, got ~w", [Version]));
parse_version(_) ->
    parse_error(bad_version, <<"truncated version field">>).

parse_section(<<Id, Rest/binary>>) ->
    Type = get_section_type(Id),
    {ok, {[{section_id, Id}, {section_type, Type}], Rest, do_parse_section(Type)}}.

get_section_type(0) -> custom;
get_section_type(1) -> type;
get_section_type(2) -> import;
get_section_type(3) -> function;
get_section_type(4) -> table;
get_section_type(5) -> memory;
get_section_type(6) -> global;
get_section_type(7) -> export;
get_section_type(8) -> start;
get_section_type(9) -> element;
get_section_type(10) -> code;
get_section_type(11) -> data;
get_section_type(12) -> data_count;
get_section_type(13) -> tag;
get_section_type(Id) ->
    parse_error(unknown_section, bin_fmt("section id ~B", [Id])).

do_parse_section(Type) ->
    fun(Binary) -> do_parse_section_len(Type, Binary) end.

do_parse_section_len(Type, Binary) ->
    {Length, Rest} = wa_parser_atomic:u32(Binary),
    {ok, {{section_length, Length}, Rest, parse_section_body(Type, Length)}}.

parse_section_body(Type, Length) ->
    fun(Binary) -> do_parse_section_body(Type, Length, Binary) end.

do_parse_section_body(Type, Len, Binary) ->
    case byte_size(Binary) < Len of
        true ->
            parse_error(section_truncated,
                        bin_fmt("~w section declares ~B bytes, only ~B available",
                                [Type, Len, byte_size(Binary)]));
        false ->
            ok
    end,

    <<Section:Len/binary, Rest/binary>> = Binary,

    case section_body(Type, Section) of
        {Body, <<>>} ->
            {ok, {{section_body, Body}, Rest, fun parse_section/1}};
        {_Body, Leftover} ->
            parse_error(unconsumed_section_bytes,
                        bin_fmt("~w section has ~B trailing byte(s)",
                                [Type, byte_size(Leftover)]))
    end.

%% tag ::= 0x00 typeidx (the attribute byte is reserved as zero)
tag(<<16#00, Rest/binary>>) ->
    {Type, Rest2} = typeidx(Rest),
    {{tag, Type}, Rest2}.

catch_clause(<<16#00, Rest/binary>>) ->
    {T, Rest1} = tagidx(Rest),
    {L, Rest2} = labelidx(Rest1),
    {{'catch', T, L}, Rest2};
catch_clause(<<16#01, Rest/binary>>) ->
    {T, Rest1} = tagidx(Rest),
    {L, Rest2} = labelidx(Rest1),
    {{catch_ref, T, L}, Rest2};
catch_clause(<<16#02, Rest/binary>>) ->
    {L, Rest2} = labelidx(Rest),
    {{catch_all, L}, Rest2};
catch_clause(<<16#03, Rest/binary>>) ->
    {L, Rest2} = labelidx(Rest),
    {{catch_all_ref, L}, Rest2}.

instr_with_immediates(Name, []) -> Name;
instr_with_immediates(Name, Args) -> {Name, Args}.

%% -- 0xFB GC immediates -----------------------------------------------------

gc_immediates(none, Rest) -> {[], Rest};

gc_immediates(type, Rest) ->
    typeidx(Rest);

gc_immediates(field, Rest) ->
    {X, Rest1} = typeidx(Rest),
    {I, Rest2} = wa_parser_atomic:u32(Rest1),
    {#{type => X, field => I}, Rest2};

gc_immediates(fixed, Rest) ->
    {X, Rest1} = typeidx(Rest),
    {N, Rest2} = wa_parser_atomic:u32(Rest1),
    {#{type => X, n => N}, Rest2};

gc_immediates(data, Rest) ->
    {X, Rest1} = typeidx(Rest),
    {Y, Rest2} = dataidx(Rest1),
    {#{type => X, data => Y}, Rest2};

gc_immediates(elem, Rest) ->
    {X, Rest1} = typeidx(Rest),
    {Y, Rest2} = elemidx(Rest1),
    {#{type => X, elem => Y}, Rest2};

gc_immediates(copy, Rest) ->
    {Dst, Rest1} = tableidx(Rest),
    {Src, Rest2} = tableidx(Rest1),
    {#{dst => Dst, src => Src}, Rest2};

gc_immediates(heap, Rest) ->
    heaptype(Rest);

gc_immediates(cast, Rest) ->
    <<CastOp, Rest1/binary>> = Rest,
    {L, Rest2} = labelidx(Rest1),
    {From, Rest3} = heaptype(Rest2),
    {To, Rest4} = heaptype(Rest3),
    {SrcNull, DstNull} =
        case CastOp of
            0 -> {false, false};
            1 -> {true, false};
            2 -> {false, true};
            3 -> {true, true}
        end,
    {#{'src_null?' => SrcNull, 'dst_null?' => DstNull, label => L, from => From, to => To},
     Rest4}.

%% -- 0xFD SIMD immediates -----------------------------------------------------

simd_immediates(none, Rest) -> {[], Rest};

simd_immediates(lane, Rest) ->
    laneidx(Rest);

simd_immediates(memarg, Rest) ->
    {#{align := Align, offset := Offset, memory := Memory}, Rest1} = memarg(Rest),
    Imm =
        case Memory of
            0 -> #{align => Align, offset => Offset};
            _ -> #{align => Align, offset => Offset, memory => Memory}
        end,
    {Imm, Rest1};

simd_immediates(memarg_lane, Rest) ->
    {#{align := Align, offset := Offset, memory := Memory}, Rest1} = memarg(Rest),
    {Lane, Rest2} = laneidx(Rest1),
    Imm =
        case Memory of
            0 -> #{align => Align, offset => Offset, lane => Lane};
            _ -> #{align => Align, offset => Offset, lane => Lane, memory => Memory}
        end,
    {Imm, Rest2};

simd_immediates(v128const, <<Val:128/unsigned-little, Rest/binary>>) ->
    {Val, Rest};

%% Shuffle takes 16 raw lane bytes - no length prefix.
simd_immediates(shuffle, Rest) ->
    <<LanesBin:16/binary, Rest1/binary>> = Rest,
    Lanes = [B || <<B>> <= LanesBin],
    {Lanes, Rest1}.

%% ============================================================================
%% Section bodies
%% ============================================================================

section_body(type, Binary) -> vec(fun rectype/1, Binary);
section_body(function, Binary) -> vec(fun typeidx/1, Binary);
section_body(table, Binary) -> vec(fun tabletype/1, Binary);
section_body(memory, Binary) -> vec(fun memtype/1, Binary);
section_body(global, Binary) -> vec(fun global/1, Binary);
section_body(export, Binary) -> vec(fun export/1, Binary);
section_body(code, Binary) -> vec(fun code/1, Binary);

section_body(custom, Binary) ->
    {N, Rest} = name(Binary),

    case N of
        <<"name">> ->
            {#{name => N, content => Rest, names => decode_name_section(Rest)}, <<>>};
        _ ->
            {#{name => N, content => Rest}, <<>>}
    end;

%% Import section: the leading u32 is the TOTAL number of imports (not the
%% number of physical entries). A standard entry yields one import; a
%% compact-import-section entry (markers 0x7F/0x7E) yields several sharing a
%% module name (and, for 0x7E, an externtype). Loop reading entries until Count
%% imports have accumulated, so the section stays a flat {Module, Name, Desc}
%% list regardless of encoding.
section_body(import, Binary) ->
    {Count, Rest} = wa_parser_atomic:u32(Binary),
    import_entries(Count, Rest, []);

section_body(start, Binary) ->
    {Idx, Rest} = funcidx(Binary),
    {{start, Idx}, Rest};

section_body(element, Binary) -> vec(fun elem_segment/1, Binary);
section_body(data, Binary) -> vec(fun data_segment/1, Binary);

section_body(data_count, Binary) ->
    {Count, Rest} = wa_parser_atomic:u32(Binary),
    {#{count => Count}, Rest};

section_body(tag, Binary) -> vec(fun tag/1, Binary).

code(Binary) ->
    {CodeSize, Rest} = wa_parser_atomic:u32(Binary),
    {Code, Rest1} = func(Rest),
    {#{size => CodeSize, code => Code}, Rest1}.

func(Binary) ->
    {Locals, Rest} = vec(fun locals/1, Binary),
    {E, Rest1} = expr(Rest),
    {#{locals => Locals, expr => E}, Rest1}.

locals(Binary) ->
    {Num, Rest} = wa_parser_atomic:u32(Binary),
    {Type, Rest1} = valtype(Rest),
    {#{num => Num, type => Type}, Rest1}.

export(Binary) ->
    {Name0, Rest} = name(Binary),
    {ExportDesc, Rest1} = exportdesc(Rest),
    {{Name0, ExportDesc}, Rest1}.

name(Binary) ->
    {Nm, Rest} = vec(fun byte/1, Binary),
    {unicode:characters_to_binary(Nm), Rest}.

byte(<<B, Rest/binary>>) -> {B, Rest};
byte(<<>>) -> parse_error(truncated, <<"name ends mid-UTF8-byte">>).

exportdesc(<<16#00, Rest/binary>>) ->
    {Fun, Rest1} = funcidx(Rest),
    {{func, Fun}, Rest1};
exportdesc(<<16#02, Rest/binary>>) ->
    {Mem, Rest1} = memidx(Rest),
    {{mem, Mem}, Rest1};
exportdesc(<<16#03, Rest/binary>>) ->
    {Glob, Rest1} = globalidx(Rest),
    {{global, Glob}, Rest1};
exportdesc(<<16#04, Rest/binary>>) ->
    {T, Rest1} = tagidx(Rest),
    {{tag, T}, Rest1}.

%% Name custom section (spec appendix): id byte + size-prefixed subsections.
decode_name_section(Binary) ->
    decode_names(Binary,
                 #{module => nil, types => #{}, funcs => #{}, tables => #{},
                   memories => #{}, globals => #{}, elems => #{}, datas => #{},
                   fields => #{}, tags => #{}, labels => #{}}).

decode_names(<<>>, Acc) ->
    Acc;
decode_names(<<Id, Rest/binary>>, Acc) ->
    {Len, Rest1} = wa_parser_atomic:u32(Rest),
    <<Data:Len/binary, Rest2/binary>> = Rest1,
    decode_names(Rest2, store_names(Id, Data, Acc)).

store_names(0, D, Acc) ->
    {Nm, <<>>} = name(D),
    Acc#{module := Nm};

store_names(Id, D, Acc) when (Id >= 1 andalso Id =< 9); Id =:= 11 ->
    Key =
        case Id of
            1 -> funcs;
            2 -> locals;
            3 -> labels;
            4 -> types;
            5 -> tables;
            6 -> memories;
            7 -> globals;
            8 -> elems;
            9 -> datas;
            11 -> tags
        end,

    case Key of
        locals ->
            {Pairs, <<>>} = vec(fun named_indirect_entry/1, D),
            Acc#{Key => maps:from_list(Pairs)};
        labels ->
            {Pairs, <<>>} = vec(fun named_indirect_entry/1, D),
            Acc#{Key => maps:from_list(Pairs)};
        _ ->
            Acc#{Key => namemap_bang(D)}
    end;

store_names(10, D, Acc) ->
    {Pairs, <<>>} = vec(fun named_indirect_entry/1, D),
    Acc#{fields => maps:from_list(Pairs)};

store_names(_Id, _D, Acc) ->
    Acc.

namemap(D) ->
    {Pairs, Rest} = vec(fun named_idx/1, D),
    {maps:from_list(Pairs), Rest}.

namemap_bang(D) ->
    {Map, <<>>} = namemap(D),
    Map.

named_idx(Binary) ->
    {Idx, Rest} = wa_parser_atomic:u32(Binary),
    {Nm, Rest1} = name(Rest),
    {{Idx, Nm}, Rest1}.

named_indirect_entry(Binary) ->
    {Outer, Rest} = wa_parser_atomic:u32(Binary),
    {Inner, Rest1} = namemap(Rest),
    {{Outer, Inner}, Rest1}.

%% Read import-section entries until Count imports have accumulated. A standard
%% entry yields one import; a compact entry yields its inner count. Decrement
%% by the number produced, not by 1.
import_entries(Remaining, Rest, Acc) when Remaining =< 0 ->
    {lists:reverse(Acc), Rest};
import_entries(Remaining, Binary, Acc) ->
    {Imports, Rest} = imported(Binary),
    import_entries(Remaining - length(Imports), Rest, lists:reverse(Imports, Acc)).

imported(Binary) ->
    {Module, Rest} = name(Binary),
    {Nm, Rest1} = name(Rest),
    imported_desc(Module, Nm, Rest1).

%% Returns {[{Module, Name, Desc}], Rest}. The standard import form yields a
%% single import; the compact-import-section forms (added below) yield a list.
%% Standard form: the byte after the module + field name is a real importdesc
%% tag (0x00..0x04). Pass the full binary so importdesc/1 consumes the tag.
imported_desc(Module, Nm, <<Tag, _/binary>> = Rest1) when Tag =< 16#04 ->
    {Desc, Rest2} = importdesc(Rest1),
    {[{Module, Nm, Desc}], Rest2};
%% Compact form A (marker 0x7F): several imports share the module name. The
%% field name must be empty; then count:u32 and count (name, externtype) items
%% follow the marker. Expands to one import per item.
imported_desc(Module, <<>>, <<16#7F, Rest/binary>>) ->
    {Items, Rest1} = vec(fun importitem/1, Rest),
    {[{Module, Nm2, Xt} || {Nm2, Xt} <- Items], Rest1};
%% Compact form B (marker 0x7E): several imports share the module name AND the
%% externtype. The field name must be empty; the shared externtype is read ONCE
%% (before the count), then count:u32 and count field names follow. Expands to
%% one import per name, all carrying the single externtype.
imported_desc(Module, <<>>, <<16#7E, Rest/binary>>) ->
    {Xt, Rest1} = importdesc(Rest),
    {Names, Rest2} = vec(fun name/1, Rest1),
    {[{Module, Nm2, Xt} || Nm2 <- Names], Rest2};
%% Compact marker (0x7F/0x7E) but the field name was NOT empty: the proposal
%% requires an empty field name for a compact entry, so this is malformed.
imported_desc(_Module, Nm, <<Marker, _/binary>>) when Marker =:= 16#7F; Marker =:= 16#7E ->
    parse_error(malformed_compact_import,
                bin_fmt("compact import marker 0x~2.16.0B requires an empty field name, got ~p",
                        [Marker, Nm]));
%% Neither a valid importdesc tag (0x00..0x04) nor a compact marker.
imported_desc(_Module, _Nm, <<Tag, _/binary>>) ->
    parse_error(invalid_importdesc,
                bin_fmt("invalid importdesc tag 0x~2.16.0B", [Tag]));
%% Entry ends before the importdesc/marker byte.
imported_desc(_Module, _Nm, <<>>) ->
    parse_error(truncated, <<"import entry ends before importdesc">>).

%% One (field name, externtype) pair inside a compact import list.
importitem(Binary) ->
    {Nm2, Rest} = name(Binary),
    {Xt, Rest1} = importdesc(Rest),
    {{Nm2, Xt}, Rest1}.

importdesc(<<16#00, Rest/binary>>) ->
    {Fun, Rest1} = typeidx(Rest),
    {{func, Fun}, Rest1};
importdesc(<<16#01, Rest/binary>>) ->
    {Tt, Rest1} = tabletype(Rest),
    {{table, Tt}, Rest1};
importdesc(<<16#02, Rest/binary>>) ->
    {Mt, Rest1} = memtype(Rest),
    {{memory, Mt}, Rest1};
importdesc(<<16#03, Rest/binary>>) ->
    {Gt, Rest1} = globaltype(Rest),
    {{global, Gt}, Rest1};
%% externtype tag = 0x04 + tagtype (reserved 0x00 attribute + typeidx)
importdesc(<<16#04, 16#00, Rest/binary>>) ->
    {T, Rest1} = typeidx(Rest),
    {{tag, T}, Rest1}.

elem_segment(<<Flag, Rest/binary>>) ->
    elem_segment(Flag, Rest).
elem_segment(16#00, Binary) ->
    {Offset, Rest} = expr(Binary),
    {Funcs, Rest1} = vec(fun funcidx/1, Rest),
    {#{flags => 0, offset => Offset, init => Funcs}, Rest1};
elem_segment(16#01, Binary) ->
    {Kind, Rest} = elemkind(Binary),
    {Funcs, Rest1} = vec(fun funcidx/1, Rest),
    {#{flags => 1, kind => Kind, init => Funcs}, Rest1};
elem_segment(16#02, Binary) ->
    {Table, Rest} = tableidx(Binary),
    {Offset, Rest1} = expr(Rest),
    {Kind, Rest2} = elemkind(Rest1),
    {Funcs, Rest3} = vec(fun funcidx/1, Rest2),
    {#{flags => 2, table => Table, offset => Offset, kind => Kind, init => Funcs}, Rest3};
elem_segment(16#03, Binary) ->
    {Kind, Rest} = elemkind(Binary),
    {Funcs, Rest1} = vec(fun funcidx/1, Rest),
    {#{flags => 3, kind => Kind, init => Funcs}, Rest1};
elem_segment(16#04, Binary) ->
    {Offset, Rest} = expr(Binary),
    {Elems, Rest1} = vec(fun expr/1, Rest),
    {#{flags => 4, offset => Offset, init => Elems}, Rest1};
elem_segment(16#05, Binary) ->
    {Rt, Rest} = reftype(Binary),
    {Elems, Rest1} = vec(fun expr/1, Rest),
    {#{flags => 5, type => Rt, init => Elems}, Rest1};
elem_segment(16#06, Binary) ->
    {Table, Rest} = tableidx(Binary),
    {Offset, Rest1} = expr(Rest),
    {Rt, Rest2} = reftype(Rest1),
    {Elems, Rest3} = vec(fun expr/1, Rest2),
    {#{flags => 6, table => Table, offset => Offset, type => Rt, init => Elems}, Rest3};
elem_segment(16#07, Binary) ->
    {Rt, Rest} = reftype(Binary),
    {Elems, Rest1} = vec(fun expr/1, Rest),
    {#{flags => 7, type => Rt, init => Elems}, Rest1}.

elemkind(<<16#00, Rest/binary>>) -> {func, Rest}.

data_segment(<<Flag, Rest/binary>>) ->
    data_segment(Flag, Rest).
data_segment(16#00, Binary) ->
    {Offset, Rest} = expr(Binary),
    {Bytes, Rest1} = vec(fun byte/1, Rest),
    {#{flags => 0, offset => Offset, init => Bytes}, Rest1};
data_segment(16#01, Binary) ->
    {Bytes, Rest} = vec(fun byte/1, Binary),
    {#{flags => 1, init => Bytes}, Rest};
data_segment(16#02, Binary) ->
    {Memory, Rest} = memidx(Binary),
    {Offset, Rest1} = expr(Rest),
    {Bytes, Rest2} = vec(fun byte/1, Rest1),
    {#{flags => 2, memory => Memory, offset => Offset, init => Bytes}, Rest2}.

global(Binary) ->
    {Gl, Rest} = globaltype(Binary),
    {Ex, Rest1} = expr(Rest),
    {{Gl, Ex}, Rest1}.

globaltype(Binary) ->
    {Vt, Rest} = valtype(Binary),
    {M, Rest1} = mut(Rest),
    {{Vt, M}, Rest1}.

mut(<<16#00, Rest/binary>>) -> {const, Rest};
mut(<<16#01, Rest/binary>>) -> {'var', Rest}.

%% ============================================================================
%% Instruction decoding
%% ============================================================================

expr(Binary) ->
    expr(Binary, []).

parse_if_else(Binary) ->
    case expr(Binary) of
        {ThenInstrs, 'else', Rest} ->
            {ElseInstrs, Rest1} = expr(Rest),
            {ThenInstrs, ElseInstrs, Rest1};
        {ThenInstrs, Rest} ->
            {ThenInstrs, [], Rest}
    end.

expr(<<16#02, Rest/binary>>, Acc) ->
    {Bt, Rest1} = blocktype(Rest),
    {Exprs, Rest2} = expr(Rest1),
    expr(Rest2, [{block, #{blocktype => Bt, instr => Exprs}} | Acc]);

expr(<<16#03, Rest/binary>>, Acc) ->
    {Bt, Rest1} = blocktype(Rest),
    {Exprs, Rest2} = expr(Rest1),
    expr(Rest2, [{loop, #{blocktype => Bt, instr => Exprs}} | Acc]);

expr(<<16#04, Rest/binary>>, Acc) ->
    {Bt, Rest1} = blocktype(Rest),
    {ThenInstrs, ElseInstrs, Rest2} = parse_if_else(Rest1),
    expr(Rest2, [{'if', #{blocktype => Bt, then => ThenInstrs, 'else' => ElseInstrs}} | Acc]);

expr(<<16#0B, Rest/binary>>, Acc) ->
    {lists:reverse(Acc), Rest};

expr(<<16#1B, Rest/binary>>, Acc) ->
    expr(Rest, [select | Acc]);

expr(<<16#0C, Rest/binary>>, Acc) ->
    {L, Rest1} = labelidx(Rest),
    expr(Rest1, [{br, L} | Acc]);

expr(<<16#0D, Rest/binary>>, Acc) ->
    {L, Rest1} = labelidx(Rest),
    expr(Rest1, [{br_if, L} | Acc]);

expr(<<16#05, Rest/binary>>, Acc) ->
    {lists:reverse(Acc), 'else', Rest};

expr(<<16#0E, Rest/binary>>, Acc) ->
    {Labels, Rest1} = vec(fun labelidx/1, Rest),
    {DefaultLabel, Rest2} = labelidx(Rest1),
    expr(Rest2, [{br_table, #{labels => Labels, default => DefaultLabel}} | Acc]);

expr(<<16#20, Rest/binary>>, Acc) ->
    {Idx, Rest1} = localidx(Rest),
    expr(Rest1, [{'local.get', Idx} | Acc]);

expr(<<16#21, Rest/binary>>, Acc) ->
    {Idx, Rest1} = localidx(Rest),
    expr(Rest1, [{'local.set', Idx} | Acc]);

expr(<<16#22, Rest/binary>>, Acc) ->
    {Idx, Rest1} = localidx(Rest),
    expr(Rest1, [{'local.tee', Idx} | Acc]);

expr(<<16#41, Rest/binary>>, Acc) ->
    {Val, Rest1} = wa_parser_atomic:i32(Rest),
    expr(Rest1, [{'i32.const', Val} | Acc]);

expr(<<16#00, Rest/binary>>, Acc) ->
    expr(Rest, [unreachable | Acc]);

expr(<<16#01, Rest/binary>>, Acc) ->
    expr(Rest, [nop | Acc]);

expr(<<16#0F, Rest/binary>>, Acc) ->
    expr(Rest, [return | Acc]);

expr(<<16#10, Rest/binary>>, Acc) ->
    {F, Rest1} = funcidx(Rest),
    expr(Rest1, [{call, F} | Acc]);

expr(<<16#11, Rest/binary>>, Acc) ->
    {Type, Rest1} = typeidx(Rest),
    {Table, Rest2} = tableidx(Rest1),
    expr(Rest2, [{call_indirect, #{type => Type, table => Table}} | Acc]);

expr(<<16#1A, Rest/binary>>, Acc) ->
    expr(Rest, [drop | Acc]);

expr(<<16#1C, Rest/binary>>, Acc) ->
    {Types, Rest1} = vec(fun valtype/1, Rest),
    expr(Rest1, [{select, Types} | Acc]);

expr(<<16#23, Rest/binary>>, Acc) ->
    {G, Rest1} = globalidx(Rest),
    expr(Rest1, [{'global.get', G} | Acc]);

expr(<<16#24, Rest/binary>>, Acc) ->
    {G, Rest1} = globalidx(Rest),
    expr(Rest1, [{'global.set', G} | Acc]);

expr(<<16#25, Rest/binary>>, Acc) ->
    {T, Rest1} = tableidx(Rest),
    expr(Rest1, [{'table.get', T} | Acc]);

expr(<<16#26, Rest/binary>>, Acc) ->
    {T, Rest1} = tableidx(Rest),
    expr(Rest1, [{'table.set', T} | Acc]);

expr(<<Op, Rest/binary>>, Acc) when Op >= 16#28, Op =< 16#3E ->
    {#{align := Align, offset := Offset, memory := Memory}, Rest1} = memarg(Rest),
    Name = load_store_instr(Op),

    Instr =
        case Memory of
            0 -> {Name, #{align => Align, offset => Offset}};
            _ -> {Name, #{align => Align, offset => Offset, memory => Memory}}
        end,

    expr(Rest1, [Instr | Acc]);

expr(<<16#3F, Rest/binary>>, Acc) ->
    {M, Rest1} = memidx(Rest),
    expr(Rest1, [{'memory.size', M} | Acc]);

expr(<<16#40, Rest/binary>>, Acc) ->
    {M, Rest1} = memidx(Rest),
    expr(Rest1, [{'memory.grow', M} | Acc]);

expr(<<16#42, Rest/binary>>, Acc) ->
    {Val, Rest1} = wa_parser_atomic:i64(Rest),
    expr(Rest1, [{'i64.const', Val} | Acc]);

expr(<<16#43, Rest/binary>>, Acc) ->
    {Val, Rest1} = wa_parser_atomic:f32(Rest),
    expr(Rest1, [{'f32.const', Val} | Acc]);

expr(<<16#44, Rest/binary>>, Acc) ->
    {Val, Rest1} = wa_parser_atomic:f64(Rest),
    expr(Rest1, [{'f64.const', Val} | Acc]);

expr(<<16#FC, Rest/binary>>, Acc) ->
    {Sub, Rest1} = wa_parser_atomic:u32(Rest),
    fc_instr(Sub, Rest1, Acc);

expr(<<16#D0, Rest/binary>>, Acc) ->
    {Ht, Rest1} = heaptype(Rest),
    expr(Rest1, [{'ref.null', Ht} | Acc]);

expr(<<16#D1, Rest/binary>>, Acc) ->
    expr(Rest, ['ref.is_null' | Acc]);

expr(<<16#D2, Rest/binary>>, Acc) ->
    {F, Rest1} = funcidx(Rest),
    expr(Rest1, [{'ref.func', F} | Acc]);

expr(<<16#12, Rest/binary>>, Acc) ->
    {F, Rest1} = funcidx(Rest),
    expr(Rest1, [{return_call, F} | Acc]);

expr(<<16#13, Rest/binary>>, Acc) ->
    {Type, Rest1} = typeidx(Rest),
    {Table, Rest2} = tableidx(Rest1),
    expr(Rest2, [{return_call_indirect, #{type => Type, table => Table}} | Acc]);

expr(<<16#08, Rest/binary>>, Acc) ->
    {T, Rest1} = tagidx(Rest),
    expr(Rest1, [{throw, T} | Acc]);

expr(<<16#0A, Rest/binary>>, Acc) ->
    expr(Rest, [throw_ref | Acc]);

expr(<<16#1F, Rest/binary>>, Acc) ->
    {Bt, Rest1} = blocktype(Rest),
    {Catches, Rest2} = vec(fun catch_clause/1, Rest1),
    {Exprs, Rest3} = expr(Rest2),
    expr(Rest3, [{try_table, #{blocktype => Bt, catches => Catches, instr => Exprs}} | Acc]);

expr(<<16#14, Rest/binary>>, Acc) ->
    {T, Rest1} = typeidx(Rest),
    expr(Rest1, [{call_ref, T} | Acc]);

expr(<<16#15, Rest/binary>>, Acc) ->
    {T, Rest1} = typeidx(Rest),
    expr(Rest1, [{return_call_ref, T} | Acc]);

expr(<<16#D3, Rest/binary>>, Acc) ->
    expr(Rest, ['ref.eq' | Acc]);

expr(<<16#D4, Rest/binary>>, Acc) ->
    expr(Rest, ['ref.as_non_null' | Acc]);

expr(<<16#D5, Rest/binary>>, Acc) ->
    {L, Rest1} = labelidx(Rest),
    expr(Rest1, [{br_on_null, L} | Acc]);

expr(<<16#D6, Rest/binary>>, Acc) ->
    {L, Rest1} = labelidx(Rest),
    expr(Rest1, [{br_on_non_null, L} | Acc]);

expr(<<16#FB, Rest/binary>>, Acc) ->
    {Sub, Rest1} = wa_parser_atomic:u32(Rest),
    {Name, Shape} = wa_parser_instr:gc(Sub),
    {Imm, Rest2} = gc_immediates(Shape, Rest1),
    expr(Rest2, [instr_with_immediates(Name, Imm) | Acc]);

expr(<<16#FD, Rest/binary>>, Acc) ->
    {Sub, Rest1} = wa_parser_atomic:u32(Rest),
    {Name, Shape} = wa_parser_instr:simd(Sub),
    {Imm, Rest2} = simd_immediates(Shape, Rest1),
    expr(Rest2, [instr_with_immediates(Name, Imm) | Acc]);

expr(<<16#FE, Rest/binary>>, Acc) ->
    {Sub, Rest1} = wa_parser_atomic:u32(Rest),
    {Name, _Shape} = wa_parser_instr:fe(Sub),
    {#{align := Align, offset := Offset, memory := Memory}, Rest2} = memarg(Rest1),
    Instr =
        case Memory of
            0 -> {Name, #{align => Align, offset => Offset}};
            _ -> {Name, #{align => Align, offset => Offset, memory => Memory}}
        end,
    expr(Rest2, [Instr | Acc]);

expr(<<Opcode, Rest/binary>>, Acc) when Opcode >= 16#45, Opcode =< 16#C4 ->
    expr(Rest, [plain_numeric_instr(Opcode) | Acc]);

expr(<<B, _/binary>>, _Acc) ->
    parse_error(unknown_opcode,
                bin_fmt("opcode 0x~2.16.0b", [B]));
expr(<<>>, _Acc) ->
    parse_error(unknown_opcode, <<"unexpected end of expression">>).

%% ============================================================================
%% Instruction name tables
%% ============================================================================

plain_numeric_instr(16#45) -> 'i32.eqz';
plain_numeric_instr(16#46) -> 'i32.eq';
plain_numeric_instr(16#47) -> 'i32.ne';
plain_numeric_instr(16#48) -> 'i32.lt_s';
plain_numeric_instr(16#49) -> 'i32.lt_u';
plain_numeric_instr(16#4A) -> 'i32.gt_s';
plain_numeric_instr(16#4B) -> 'i32.gt_u';
plain_numeric_instr(16#4C) -> 'i32.le_s';
plain_numeric_instr(16#4D) -> 'i32.le_u';
plain_numeric_instr(16#4E) -> 'i32.ge_s';
plain_numeric_instr(16#4F) -> 'i32.ge_u';
plain_numeric_instr(16#50) -> 'i64.eqz';
plain_numeric_instr(16#51) -> 'i64.eq';
plain_numeric_instr(16#52) -> 'i64.ne';
plain_numeric_instr(16#53) -> 'i64.lt_s';
plain_numeric_instr(16#54) -> 'i64.lt_u';
plain_numeric_instr(16#55) -> 'i64.gt_s';
plain_numeric_instr(16#56) -> 'i64.gt_u';
plain_numeric_instr(16#57) -> 'i64.le_s';
plain_numeric_instr(16#58) -> 'i64.le_u';
plain_numeric_instr(16#59) -> 'i64.ge_s';
plain_numeric_instr(16#5A) -> 'i64.ge_u';
plain_numeric_instr(16#5B) -> 'f32.eq';
plain_numeric_instr(16#5C) -> 'f32.ne';
plain_numeric_instr(16#5D) -> 'f32.lt';
plain_numeric_instr(16#5E) -> 'f32.gt';
plain_numeric_instr(16#5F) -> 'f32.le';
plain_numeric_instr(16#60) -> 'f32.ge';
plain_numeric_instr(16#61) -> 'f64.eq';
plain_numeric_instr(16#62) -> 'f64.ne';
plain_numeric_instr(16#63) -> 'f64.lt';
plain_numeric_instr(16#64) -> 'f64.gt';
plain_numeric_instr(16#65) -> 'f64.le';
plain_numeric_instr(16#66) -> 'f64.ge';
plain_numeric_instr(16#67) -> 'i32.clz';
plain_numeric_instr(16#68) -> 'i32.ctz';
plain_numeric_instr(16#69) -> 'i32.popcnt';
plain_numeric_instr(16#6A) -> 'i32.add';
plain_numeric_instr(16#6B) -> 'i32.sub';
plain_numeric_instr(16#6C) -> 'i32.mul';
plain_numeric_instr(16#6D) -> 'i32.div_s';
plain_numeric_instr(16#6E) -> 'i32.div_u';
plain_numeric_instr(16#6F) -> 'i32.rem_s';
plain_numeric_instr(16#70) -> 'i32.rem_u';
plain_numeric_instr(16#71) -> 'i32.and';
plain_numeric_instr(16#72) -> 'i32.or';
plain_numeric_instr(16#73) -> 'i32.xor';
plain_numeric_instr(16#74) -> 'i32.shl';
plain_numeric_instr(16#75) -> 'i32.shr_s';
plain_numeric_instr(16#76) -> 'i32.shr_u';
plain_numeric_instr(16#77) -> 'i32.rotl';
plain_numeric_instr(16#78) -> 'i32.rotr';
plain_numeric_instr(16#79) -> 'i64.clz';
plain_numeric_instr(16#7A) -> 'i64.ctz';
plain_numeric_instr(16#7B) -> 'i64.popcnt';
plain_numeric_instr(16#7C) -> 'i64.add';
plain_numeric_instr(16#7D) -> 'i64.sub';
plain_numeric_instr(16#7E) -> 'i64.mul';
plain_numeric_instr(16#7F) -> 'i64.div_s';
plain_numeric_instr(16#80) -> 'i64.div_u';
plain_numeric_instr(16#81) -> 'i64.rem_s';
plain_numeric_instr(16#82) -> 'i64.rem_u';
plain_numeric_instr(16#83) -> 'i64.and';
plain_numeric_instr(16#84) -> 'i64.or';
plain_numeric_instr(16#85) -> 'i64.xor';
plain_numeric_instr(16#86) -> 'i64.shl';
plain_numeric_instr(16#87) -> 'i64.shr_s';
plain_numeric_instr(16#88) -> 'i64.shr_u';
plain_numeric_instr(16#89) -> 'i64.rotl';
plain_numeric_instr(16#8A) -> 'i64.rotr';
plain_numeric_instr(16#8B) -> 'f32.abs';
plain_numeric_instr(16#8C) -> 'f32.neg';
plain_numeric_instr(16#8D) -> 'f32.ceil';
plain_numeric_instr(16#8E) -> 'f32.floor';
plain_numeric_instr(16#8F) -> 'f32.trunc';
plain_numeric_instr(16#90) -> 'f32.nearest';
plain_numeric_instr(16#91) -> 'f32.sqrt';
plain_numeric_instr(16#92) -> 'f32.add';
plain_numeric_instr(16#93) -> 'f32.sub';
plain_numeric_instr(16#94) -> 'f32.mul';
plain_numeric_instr(16#95) -> 'f32.div';
plain_numeric_instr(16#96) -> 'f32.min';
plain_numeric_instr(16#97) -> 'f32.max';
plain_numeric_instr(16#98) -> 'f32.copysign';
plain_numeric_instr(16#99) -> 'f64.abs';
plain_numeric_instr(16#9A) -> 'f64.neg';
plain_numeric_instr(16#9B) -> 'f64.ceil';
plain_numeric_instr(16#9C) -> 'f64.floor';
plain_numeric_instr(16#9D) -> 'f64.trunc';
plain_numeric_instr(16#9E) -> 'f64.nearest';
plain_numeric_instr(16#9F) -> 'f64.sqrt';
plain_numeric_instr(16#A0) -> 'f64.add';
plain_numeric_instr(16#A1) -> 'f64.sub';
plain_numeric_instr(16#A2) -> 'f64.mul';
plain_numeric_instr(16#A3) -> 'f64.div';
plain_numeric_instr(16#A4) -> 'f64.min';
plain_numeric_instr(16#A5) -> 'f64.max';
plain_numeric_instr(16#A6) -> 'f64.copysign';
plain_numeric_instr(16#A7) -> 'i32.wrap_i64';
plain_numeric_instr(16#A8) -> 'i32.trunc_f32_s';
plain_numeric_instr(16#A9) -> 'i32.trunc_f32_u';
plain_numeric_instr(16#AA) -> 'i32.trunc_f64_s';
plain_numeric_instr(16#AB) -> 'i32.trunc_f64_u';
plain_numeric_instr(16#AC) -> 'i64.extend_i32_s';
plain_numeric_instr(16#AD) -> 'i64.extend_i32_u';
plain_numeric_instr(16#AE) -> 'i64.trunc_f32_s';
plain_numeric_instr(16#AF) -> 'i64.trunc_f32_u';
plain_numeric_instr(16#B0) -> 'i64.trunc_f64_s';
plain_numeric_instr(16#B1) -> 'i64.trunc_f64_u';
plain_numeric_instr(16#B2) -> 'f32.convert_i32_s';
plain_numeric_instr(16#B3) -> 'f32.convert_i32_u';
plain_numeric_instr(16#B4) -> 'f32.convert_i64_s';
plain_numeric_instr(16#B5) -> 'f32.convert_i64_u';
plain_numeric_instr(16#B6) -> 'f32.demote_f64';
plain_numeric_instr(16#B7) -> 'f64.convert_i32_s';
plain_numeric_instr(16#B8) -> 'f64.convert_i32_u';
plain_numeric_instr(16#B9) -> 'f64.convert_i64_s';
plain_numeric_instr(16#BA) -> 'f64.convert_i64_u';
plain_numeric_instr(16#BB) -> 'f64.promote_f32';
plain_numeric_instr(16#BC) -> 'i32.reinterpret_f32';
plain_numeric_instr(16#BD) -> 'i64.reinterpret_f64';
plain_numeric_instr(16#BE) -> 'f32.reinterpret_i32';
plain_numeric_instr(16#BF) -> 'f64.reinterpret_i64';
plain_numeric_instr(16#C0) -> 'i32.extend8_s';
plain_numeric_instr(16#C1) -> 'i32.extend16_s';
plain_numeric_instr(16#C2) -> 'i64.extend8_s';
plain_numeric_instr(16#C3) -> 'i64.extend16_s';
plain_numeric_instr(16#C4) -> 'i64.extend32_s'.

load_store_instr(16#28) -> 'i32.load';
load_store_instr(16#29) -> 'i64.load';
load_store_instr(16#2A) -> 'f32.load';
load_store_instr(16#2B) -> 'f64.load';
load_store_instr(16#2C) -> 'i32.load8_s';
load_store_instr(16#2D) -> 'i32.load8_u';
load_store_instr(16#2E) -> 'i32.load16_s';
load_store_instr(16#2F) -> 'i32.load16_u';
load_store_instr(16#30) -> 'i64.load8_s';
load_store_instr(16#31) -> 'i64.load8_u';
load_store_instr(16#32) -> 'i64.load16_s';
load_store_instr(16#33) -> 'i64.load16_u';
load_store_instr(16#34) -> 'i64.load32_s';
load_store_instr(16#35) -> 'i64.load32_u';
load_store_instr(16#36) -> 'i32.store';
load_store_instr(16#37) -> 'i64.store';
load_store_instr(16#38) -> 'f32.store';
load_store_instr(16#39) -> 'f64.store';
load_store_instr(16#3A) -> 'i32.store8';
load_store_instr(16#3B) -> 'i32.store16';
load_store_instr(16#3C) -> 'i64.store8';
load_store_instr(16#3D) -> 'i64.store16';
load_store_instr(16#3E) -> 'i64.store32'.

fc_instr(0, Rest, Acc) -> expr(Rest, ['i32.trunc_sat_f32_s' | Acc]);
fc_instr(1, Rest, Acc) -> expr(Rest, ['i32.trunc_sat_f32_u' | Acc]);
fc_instr(2, Rest, Acc) -> expr(Rest, ['i32.trunc_sat_f64_s' | Acc]);
fc_instr(3, Rest, Acc) -> expr(Rest, ['i32.trunc_sat_f64_u' | Acc]);
fc_instr(4, Rest, Acc) -> expr(Rest, ['i64.trunc_sat_f32_s' | Acc]);
fc_instr(5, Rest, Acc) -> expr(Rest, ['i64.trunc_sat_f32_u' | Acc]);
fc_instr(6, Rest, Acc) -> expr(Rest, ['i64.trunc_sat_f64_s' | Acc]);
fc_instr(7, Rest, Acc) -> expr(Rest, ['i64.trunc_sat_f64_u' | Acc]);

fc_instr(8, Rest, Acc) ->
    {Data, Rest1} = dataidx(Rest),
    {Memory, Rest2} = memidx(Rest1),
    expr(Rest2, [{'memory.init', #{data => Data, memory => Memory}} | Acc]);

fc_instr(9, Rest, Acc) ->
    {Data, Rest1} = dataidx(Rest),
    expr(Rest1, [{'data.drop', Data} | Acc]);

fc_instr(10, Rest, Acc) ->
    {Dst, Rest1} = memidx(Rest),
    {Src, Rest2} = memidx(Rest1),
    expr(Rest2, [{'memory.copy', #{dst => Dst, src => Src}} | Acc]);

fc_instr(11, Rest, Acc) ->
    {Memory, Rest1} = memidx(Rest),
    expr(Rest1, [{'memory.fill', Memory} | Acc]);

fc_instr(12, Rest, Acc) ->
    {Elem, Rest1} = elemidx(Rest),
    {Table, Rest2} = tableidx(Rest1),
    expr(Rest2, [{'table.init', #{elem => Elem, table => Table}} | Acc]);

fc_instr(13, Rest, Acc) ->
    {Elem, Rest1} = elemidx(Rest),
    expr(Rest1, [{'elem.drop', Elem} | Acc]);

fc_instr(14, Rest, Acc) ->
    {Dst, Rest1} = tableidx(Rest),
    {Src, Rest2} = tableidx(Rest1),
    expr(Rest2, [{'table.copy', #{dst => Dst, src => Src}} | Acc]);

fc_instr(15, Rest, Acc) ->
    {Table, Rest1} = tableidx(Rest),
    expr(Rest1, [{'table.grow', Table} | Acc]);

fc_instr(16, Rest, Acc) ->
    {Table, Rest1} = tableidx(Rest),
    expr(Rest1, [{'table.size', Table} | Acc]);

fc_instr(17, Rest, Acc) ->
    {Table, Rest1} = tableidx(Rest),
    expr(Rest1, [{'table.fill', Table} | Acc]).

%% ============================================================================
%% Types
%% ============================================================================

blocktype(<<16#40, Rest/binary>>) ->
    {empty, Rest};

%% Non-negative s33 is a type index; negative encodings are value types
%% (number/vector bytes, abstract heap shorthand bytes, or the multi-byte
%% ref/ref-null markers whose heap type follows).
blocktype(Binary) ->
    {V, Rest} = wa_parser_atomic:s33(Binary),

    case V >= 0 of
        true ->
            {{typeidx, V}, Rest};
        false ->
            case V of
                -29 ->
                    {Ht, Rest1} = heaptype(Rest),
                    {{ref_null, Ht}, Rest1};
                -30 ->
                    {Ht, Rest1} = heaptype(Rest),
                    {{ref, Ht}, Rest1};
                _ ->
                    {neg_valtype(V), Rest}
            end
    end.

neg_valtype(-1) -> i32;
neg_valtype(-2) -> i64;
neg_valtype(-3) -> f32;
neg_valtype(-4) -> f64;
neg_valtype(-5) -> v128;
neg_valtype(V) when V >= -23, V =< -13 -> abs_heap_atom(V);
neg_valtype(V) ->
    parse_error(unknown_type,
                bin_fmt("unrecognized negative type encoding ~B", [V])).

memtype(Binary) ->
    limits(Binary).

%% Heap types are encoded as s33: negative values name abstract types,
%% non-negative values are concrete type indices.
heaptype(Binary) ->
    {V, Rest} = wa_parser_atomic:s33(Binary),

    Ht =
        case V of
            -16 -> func;
            -17 -> extern;
            -18 -> any;
            -19 -> eq;
            -20 -> i31;
            -21 -> struct;
            -22 -> array;
            -15 -> none;
            -14 -> noextern;
            -13 -> nofunc;
            -12 -> noexn;
            -23 -> exn;
            _ when V >= 0 -> {typeidx, V}
        end,

    {Ht, Rest}.

tabletype(Binary) ->
    {Et, Rest} = reftype(Binary),
    {Lim, Rest1} = limits(Rest),
    {{Et, Lim}, Rest1}.

reftype(<<16#70, Rest/binary>>) ->
    {funcref, Rest};
reftype(<<16#6F, Rest/binary>>) ->
    {externref, Rest};
reftype(<<16#63, Rest/binary>>) ->
    {Ht, Rest1} = heaptype(Rest),
    {{ref_null, Ht}, Rest1};
reftype(<<16#64, Rest/binary>>) ->
    {Ht, Rest1} = heaptype(Rest),
    {{ref, Ht}, Rest1};
%% Remaining abstract heap bytes act as shorthand for ref null <ht>.
reftype(<<B, Rest/binary>>) when (B >= 16#69 andalso B =< 16#6E);
                                 (B >= 16#71 andalso B =< 16#74) ->
    Ht = abs_heap_atom(B - 128),
    {{ref_null, Ht}, Rest}.

abs_heap_atom(-23) -> exn;
abs_heap_atom(-22) -> array;
abs_heap_atom(-21) -> struct;
abs_heap_atom(-20) -> i31;
abs_heap_atom(-19) -> eq;
abs_heap_atom(-18) -> any;
abs_heap_atom(-17) -> extern;
abs_heap_atom(-16) -> func;
abs_heap_atom(-15) -> none;
abs_heap_atom(-14) -> noextern;
abs_heap_atom(-13) -> nofunc;
abs_heap_atom(-12) -> noexn.

memarg(Binary) ->
    {Flags, Rest} = wa_parser_atomic:u32(Binary),

    {Memory, Rest1} =
        case Flags >= 64 of
            true -> wa_parser_atomic:u32(Rest);
            false -> {0, Rest}
        end,

    Align =
        case Flags >= 64 of
            true -> Flags - 64;
            false -> Flags
        end,

    {Offset, Rest2} = wa_parser_atomic:u64(Rest1),
    {#{align => Align, offset => Offset, memory => Memory}, Rest2}.

limits(<<16#00, Rest/binary>>) ->
    {Min, Rest1} = wa_parser_atomic:u32(Rest),
    {{Min, nil}, Rest1};
limits(<<16#01, Rest/binary>>) ->
    {Min, Rest1} = wa_parser_atomic:u32(Rest),
    {Max, Rest2} = wa_parser_atomic:u32(Rest1),
    {{Min, Max}, Rest2};
limits(<<16#02, Rest/binary>>) ->
    {Min, Rest1} = wa_parser_atomic:u32(Rest),
    {{Min, nil, shared}, Rest1};
limits(<<16#03, Rest/binary>>) ->
    {Min, Rest1} = wa_parser_atomic:u32(Rest),
    {Max, Rest2} = wa_parser_atomic:u32(Rest1),
    {{Min, Max, shared}, Rest2};
limits(<<16#04, Rest/binary>>) ->
    {Min, Rest1} = wa_parser_atomic:u64(Rest),
    {{Min, nil, i64}, Rest1};
limits(<<16#05, Rest/binary>>) ->
    {Min, Rest1} = wa_parser_atomic:u64(Rest),
    {Max, Rest2} = wa_parser_atomic:u64(Rest1),
    {{Min, Max, i64}, Rest2}.

valtype(<<16#7F, Rest/binary>>) -> {i32, Rest};
valtype(<<16#7E, Rest/binary>>) -> {i64, Rest};
valtype(<<16#7D, Rest/binary>>) -> {f32, Rest};
valtype(<<16#7C, Rest/binary>>) -> {f64, Rest};
valtype(<<16#7B, Rest/binary>>) -> {v128, Rest};
valtype(Binary) -> reftype(Binary).

%% Recursive types: explicit rec wrapper or bare subtype shorthand.
rectype(<<16#4E, Rest/binary>>) ->
    {Subs, Rest1} = vec(fun subtype/1, Rest),
    {#{rec => Subs}, Rest1};
rectype(Binary) ->
    subtype(Binary).

subtype(<<16#50, Rest/binary>>) ->
    {Supers, Rest1} = vec(fun typeidx/1, Rest),
    {Ct, Rest2} = comptype(Rest1),
    {#{supers => Supers, final => false, type => Ct}, Rest2};
subtype(<<16#4F, Rest/binary>>) ->
    {Supers, Rest1} = vec(fun typeidx/1, Rest),
    {Ct, Rest2} = comptype(Rest1),
    {#{supers => Supers, final => true, type => Ct}, Rest2};
subtype(Binary) ->
    comptype(Binary).

%% Composite types: func / struct / array
comptype(<<16#60, _/binary>> = Bin) ->
    functype(Bin);
comptype(<<16#5E, Rest/binary>>) ->
    {Ft, Rest1} = fieldtype(Rest),
    {#{array => Ft}, Rest1};
comptype(<<16#5F, Rest/binary>>) ->
    {Fields, Rest1} = vec(fun fieldtype/1, Rest),
    {#{struct => Fields}, Rest1}.

functype(<<16#60, Rest/binary>>) ->
    {ParamType, Rest1} = resulttype(Rest),
    {ResultType, Rest2} = resulttype(Rest1),
    {{ParamType, ResultType}, Rest2}.

fieldtype(Binary) ->
    {St, Rest} = storagetype(Binary),
    {Mu, Rest1} = mut(Rest),
    {#{type => St, mut => Mu}, Rest1}.

storagetype(<<16#78, Rest/binary>>) -> {i8, Rest};
storagetype(<<16#77, Rest/binary>>) -> {i16, Rest};
storagetype(Binary) -> valtype(Binary).

resulttype(Binary) ->
    vec(fun valtype/1, Binary).

%% ============================================================================
%% Indexed vectors and helpers
%% ============================================================================

vec(Type, Binary) ->
    {Length, Rest} = wa_parser_atomic:u32(Binary),
    do_vec(Type, Length, Rest, []).

do_vec(_Type, 0, Rest, Acc) ->
    {lists:reverse(Acc), Rest};
do_vec(Type, Length, Binary, Acc) ->
    {V, Rest} = Type(Binary),
    do_vec(Type, Length - 1, Rest, [V | Acc]).

funcidx(Binary) -> wa_parser_atomic:u32(Binary).
globalidx(Binary) -> wa_parser_atomic:u32(Binary).
labelidx(Binary) -> wa_parser_atomic:u32(Binary).
localidx(Binary) -> wa_parser_atomic:u32(Binary).
memidx(Binary) -> wa_parser_atomic:u32(Binary).
typeidx(Binary) -> wa_parser_atomic:u32(Binary).
tableidx(Binary) -> wa_parser_atomic:u32(Binary).
dataidx(Binary) -> wa_parser_atomic:u32(Binary).
elemidx(Binary) -> wa_parser_atomic:u32(Binary).
tagidx(Binary) -> wa_parser_atomic:u32(Binary).
laneidx(Binary) -> wa_parser_atomic:u32(Binary).

%% ============================================================================
%% Error helpers
%% ============================================================================

bin_fmt(Fmt, Args) ->
    iolist_to_binary(io_lib:format(Fmt, Args)).

parse_error(Reason, Detail) ->
    erlang:error({parse_error, Reason, Detail}).
