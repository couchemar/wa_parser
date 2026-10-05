defmodule WaParserTest do
  use ExUnit.Case

  @wat_build_dir Path.expand("../../test_data/wat", __DIR__)

  defp parse_wat_sections(name) do
    @wat_build_dir
    |> Path.join(name <> ".wasm")
    |> parse_file()
    |> Enum.filter(fn {k, _} -> k == :section_type or k == :section_body end)
  end

  @header <<0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00>>

  defp parse_binary(bin), do: bin |> WaParser.stream() |> Enum.to_list()

  def parse_file(filename) do
    filename
    |> File.read!()
    |> WaParser.stream()
    |> Enum.to_list()
  end

  describe "unit: wat fixtures" do
    # Hand-written fixtures built by CMake/Ninja (wat2wasm) via test_helper.exs.
    # Same sources live in ../wa_embedder/test_data/wat/ - keep the two copies in sync.
    test "wat: 0_return_0" do
      assert parse_wat_sections("0_return_0") == [
               section_type: :type,
               section_body: [{[], [:i32]}],
               section_type: :function,
               section_body: [0],
               section_type: :export,
               section_body: [{"return_0", {:func, 0}}],
               section_type: :code,
               section_body: [%{code: %{expr: ["i32.const": 0], locals: []}, size: 4}]
             ]
    end

    test "wat: 1_int_identity" do
      assert parse_wat_sections("1_int_identity") == [
               section_type: :type,
               section_body: [{[:i32], [:i32]}],
               section_type: :function,
               section_body: [0],
               section_type: :export,
               section_body: [{"identity", {:func, 0}}],
               section_type: :code,
               section_body: [%{code: %{expr: ["local.get": 0], locals: []}, size: 4}]
             ]
    end

    test "wat: 3_int_cond_select" do
      assert parse_wat_sections("3_int_cond_select") == [
               section_type: :type,
               section_body: [{[:i32, :i32], [:i32]}],
               section_type: :function,
               section_body: [0],
               section_type: :export,
               section_body: [{"ge_select", {:func, 0}}],
               section_type: :code,
               section_body: [
                 %{
                   code: %{
                     expr: [
                       {:"local.get", 0},
                       {:"local.get", 1},
                       {:"local.get", 0},
                       {:"local.get", 1},
                       :"i32.ge_s",
                       :select
                     ],
                     locals: []
                   },
                   size: 12
                 }
               ]
             ]
    end

    test "wat: 5_if_else" do
      assert parse_wat_sections("5_if_else") == [
               section_type: :type,
               section_body: [{[:i32, :i32], [:i32]}],
               section_type: :function,
               section_body: [0],
               section_type: :export,
               section_body: [{"max", {:func, 0}}],
               section_type: :code,
               section_body: [
                 %{
                   code: %{
                     expr: [
                       {:"local.get", 0},
                       {:"local.get", 1},
                       :"i32.gt_s",
                       {:if,
                        %{
                          else: ["local.get": 1],
                          then: ["local.get": 0],
                          blocktype: :i32
                        }}
                     ],
                     locals: []
                   },
                   size: 15
                 }
               ]
             ]
    end

    test "wat: 9_br_table" do
      assert parse_wat_sections("9_br_table") == [
               section_type: :type,
               section_body: [{[:i32], [:i32]}],
               section_type: :function,
               section_body: [0],
               section_type: :export,
               section_body: [{"pick", {:func, 0}}],
               section_type: :code,
               section_body: [
                 %{
                   code: %{
                     expr: [
                       "i32.const": 30,
                       "local.set": 1,
                       block: %{
                         blocktype: :empty,
                         instr: [
                           block: %{
                             blocktype: :empty,
                             instr: [
                               block: %{
                                 blocktype: :empty,
                                 instr: [
                                   "local.get": 0,
                                   br_table: %{default: 2, labels: [0, 1]}
                                 ]
                               },
                               "i32.const": 10,
                               "local.set": 1,
                               br: 1
                             ]
                           },
                           "i32.const": 20,
                           "local.set": 1
                         ]
                       },
                       "local.get": 1
                     ],
                     locals: [%{type: :i32, num: 1}]
                   },
                   size: 36
                 }
               ]
             ]
    end

    test "wat: 10_block_typeidx" do
      assert parse_wat_sections("10_block_typeidx") == [
               section_type: :type,
               section_body: [{[], [:i32, :i32]}],
               section_type: :function,
               section_body: [0],
               section_type: :export,
               section_body: [{"two", {:func, 0}}],
               section_type: :code,
               section_body: [
                 %{
                   code: %{
                     expr: [
                       block: %{
                         blocktype: {:typeidx, 0},
                         instr: ["i32.const": 1, "i32.const": 2]
                       }
                     ],
                     locals: []
                   },
                   size: 9
                 }
               ]
             ]
    end

    test "wat: 11_call_import" do
      assert parse_wat_sections("11_call_import") == [
               section_type: :type,
               section_body: [{[:i32], []}],
               section_type: :import,
               section_body: [{"env", "ext", {:func, 0}}],
               section_type: :function,
               section_body: [0],
               section_type: :export,
               section_body: [{"run", {:func, 1}}],
               section_type: :code,
               section_body: [
                 %{
                   code: %{
                     expr: [
                       {:"local.get", 0},
                       {:call, 0},
                       :nop,
                       {:"local.get", 0},
                       :"i32.eqz",
                       {:if, %{else: [], then: [:return], blocktype: :empty}},
                       {:"i32.const", 0},
                       :drop
                     ],
                     locals: []
                   },
                   size: 17
                 }
               ]
             ]
    end

    test "wat: 22_compact_import (compact form A via --enable-compact-imports)" do
      # Two imports share the module name "env"; wat2wasm emits a single compact
      # (0x7F) entry. The parser must flatten it back into two individual imports
      # with the shared module name applied to each.
      sections =
        parse_wat_sections("22_compact_import")
        |> Enum.filter(fn {k, _} -> k in [:section_type, :section_body] end)

      import_body =
        sections
        |> Enum.chunk_every(2)
        |> Enum.find_value(fn
          [{:section_type, :import}, {:section_body, body}] -> body
          _ -> nil
        end)

      assert import_body == [{"env", "a", {:func, 0}}, {"env", "b", {:func, 1}}]
    end

    test "wat: 12_memory_data" do
      assert parse_wat_sections("12_memory_data") == [
               section_type: :type,
               section_body: [{[], []}],
               section_type: :function,
               section_body: [0],
               section_type: :table,
               section_body: [funcref: {2, nil}],
               section_type: :memory,
               section_body: [{1, 2}],
               section_type: :global,
               section_body: [{{:i32, :var}, ["i32.const": 42]}],
               section_type: :export,
               section_body: [{"mem", {:mem, 0}}, {"init", {:func, 0}}],
               section_type: :start,
               section_body: {:start, 0},
               section_type: :element,
               section_body: [%{flags: 0, init: [0], offset: ["i32.const": 0]}],
               section_type: :code,
               section_body: [
                 %{
                   code: %{
                     expr: [
                       "i32.const": 0,
                       "i32.const": 7,
                       "i32.store": %{offset: 8, align: 2},
                       "memory.size": 0,
                       "global.set": 0
                     ],
                     locals: []
                   },
                   size: 13
                 }
               ],
               section_type: :data,
               section_body: [
                 %{flags: 0, init: [1, 2, 3], offset: ["i32.const": 0]},
                 %{flags: 1, init: [255]}
               ]
             ]
    end

    test "wat: 13_numerics" do
      assert parse_wat_sections("13_numerics") == [
               section_type: :type,
               section_body: [{[:i32], [:f64]}, {[:f32], [:i32]}],
               section_type: :function,
               section_body: [0, 1],
               section_type: :export,
               section_body: [{"mix", {:func, 0}}, {"sat", {:func, 1}}],
               section_type: :code,
               section_body: [
                 %{
                   code: %{
                     expr: [
                       {:"f64.const", 1.5},
                       {:"local.get", 0},
                       :"i32.extend8_s",
                       :"f64.convert_i32_u",
                       :"f64.add"
                     ],
                     locals: []
                   },
                   size: 16
                 },
                 %{
                   code: %{expr: [{:"local.get", 0}, :"i32.trunc_sat_f32_s"], locals: []},
                   size: 6
                 }
               ]
             ]
    end

    # An Erlang float cannot hold infinity or NaN, and matching those bit
    # patterns with a float-type binary fails rather than yielding a value, so
    # non-finite constants decode to `+inf`/`-inf` or a sign-and-payload tuple.
    # Finite constants stay ordinary floats. Both paths are pinned here because
    # a desync anywhere past the first `inf` used to abort a whole-module parse.
    # Payloads are the raw fraction field, quiet bit included: a bare `nan` is
    # 0x400000, while `nan:0x1234` is 0x1234.
    test "wat: 23_float_nonfinite" do
      assert parse_wat_sections("23_float_nonfinite") == [
               section_type: :type,
               section_body: [{[], []}],
               section_type: :function,
               section_body: [0, 0],
               section_type: :export,
               section_body: [{"f32_nonfinite", {:func, 0}}, {"f64_nonfinite", {:func, 1}}],
               section_type: :code,
               section_body: [
                 %{
                   code: %{
                     expr: [
                       {:"f32.const", 1.5},
                       :drop,
                       {:"f32.const", :"+inf"},
                       :drop,
                       {:"f32.const", :"-inf"},
                       :drop,
                       {:"f32.const", {:nan, 0x400000}},
                       :drop,
                       {:"f32.const", {:"-nan", 0x1234}},
                       :drop
                     ],
                     locals: []
                   },
                   size: 32
                 },
                 %{
                   code: %{
                     expr: [
                       {:"f64.const", 1.5},
                       :drop,
                       {:"f64.const", :"+inf"},
                       :drop,
                       {:"f64.const", :"-inf"},
                       :drop,
                       {:"f64.const", {:nan, 0x8000000000000}},
                       :drop
                     ],
                     locals: []
                   },
                   size: 42
                 }
               ]
             ]
    end

    # The real-world shape, not a toy: the constant sits inside nested
    # `if`/`block`, and there is live code after it. A body is accumulated as a
    # stream, so failing at the constant desyncs the remainder of the body
    # instead of just that instruction — which is how one NaN in the QuickJS
    # module aborted the parse of all 1468 function bodies.
    test "wat: 24_float_nonfinite_nested" do
      assert parse_wat_sections("24_float_nonfinite_nested") == [
               section_type: :type,
               section_body: [{[:f64], [:f64]}],
               section_type: :function,
               section_body: [0],
               section_type: :export,
               section_body: [{"scale", {:func, 0}}],
               section_type: :code,
               section_body: [
                 %{
                   code: %{
                     expr: [
                       {:"f64.const", 1.5},
                       {:"local.set", 1},
                       {:"local.get", 0},
                       {:"f64.const", 0.0},
                       :"f64.eq",
                       {:if,
                        %{
                          else: [],
                          then: [
                            {:"f64.const", :"+inf"},
                            {:"local.set", 1},
                            {:block,
                             %{
                               blocktype: :f64,
                               instr: [
                                 {:"local.get", 1},
                                 {:"f64.const", {:nan, 0x8000000000000}},
                                 :"f64.mul",
                                 {:br, 0}
                               ]
                             }},
                            :drop
                          ],
                          blocktype: :empty
                        }},
                       {:"local.get", 1},
                       {:"f64.const", :"-inf"},
                       :"f64.add"
                     ],
                     locals: [%{type: :f64, num: 1}]
                   },
                   size: 71
                 }
               ]
             ]
    end

    test "wat: 14_bulk" do
      assert parse_wat_sections("14_bulk") == [
               section_type: :type,
               section_body: [{[], [:i32]}],
               section_type: :function,
               section_body: [0, 0],
               section_type: :table,
               section_body: [funcref: {4, nil}],
               section_type: :memory,
               section_body: [{1, nil}],
               section_type: :export,
               section_body: [{"run", {:func, 1}}],
               section_type: :element,
               section_body: [%{flags: 1, init: [0], kind: :func}],
               section_type: :data_count,
               section_body: %{count: 1},
               section_type: :code,
               section_body: [
                 %{code: %{expr: ["i32.const": 7], locals: []}, size: 4},
                 %{
                   code: %{
                     expr: [
                       {:"i32.const", 0},
                       {:"i32.const", 0},
                       {:"i32.const", 2},
                       {:"memory.init", %{data: 0, memory: 0}},
                       {:"data.drop", 0},
                       {:"i32.const", 0},
                       {:"i32.const", 65},
                       {:"i32.const", 2},
                       {:"memory.fill", 0},
                       {:"i32.const", 0},
                       {:"i32.const", 1},
                       {:"i32.const", 1},
                       {:"memory.copy", %{dst: 0, src: 0}},
                       {:"i32.const", 0},
                       {:"i32.const", 0},
                       {:"i32.const", 1},
                       {:"table.init", %{table: 0, elem: 0}},
                       {:"table.size", 0},
                       :drop,
                       {:"i32.const", 0},
                       {:call_indirect, %{table: 0, type: 0}}
                     ],
                     locals: []
                   },
                   size: 54
                 }
               ],
               section_type: :data,
               section_body: [%{flags: 1, init: [1, 2]}]
             ]
    end

    test "wat: 15_refs" do
      assert parse_wat_sections("15_refs") == [
               section_type: :type,
               section_body: [{[], [:i32]}],
               section_type: :function,
               section_body: [0, 0],
               section_type: :table,
               section_body: [funcref: {2, nil}],
               section_type: :memory,
               section_body: [{1, nil}],
               section_type: :export,
               section_body: [{"run", {:func, 1}}],
               section_type: :element,
               section_body: [%{flags: 3, init: [0], kind: :func}],
               section_type: :code,
               section_body: [
                 %{code: %{expr: ["i32.const": 7], locals: []}, size: 4},
                 %{
                   code: %{
                     expr: [
                       {:"i32.const", 0},
                       {:"ref.func", 0},
                       {:"table.set", 0},
                       {:"ref.null", :func},
                       {:"i32.const", 1},
                       {:"table.grow", 0},
                       :drop,
                       {:"ref.null", :func},
                       :"ref.is_null",
                       {:if, %{else: [], then: [:nop], blocktype: :empty}},
                       {:"i32.const", 1},
                       {:"ref.null", :func},
                       {:"i32.const", 1},
                       {:"table.fill", 0},
                       {:"i32.const", 0},
                       {:call_indirect, %{table: 0, type: 0}}
                     ],
                     locals: []
                   },
                   size: 37
                 }
               ]
             ]
    end

    test "wat: 16_tailcall" do
      assert parse_wat_sections("16_tailcall") == [
               section_type: :type,
               section_body: [{[], [:i32]}],
               section_type: :function,
               section_body: [0, 0, 0],
               section_type: :table,
               section_body: [funcref: {1, nil}],
               section_type: :export,
               section_body: [{"direct", {:func, 1}}, {"indirect", {:func, 2}}],
               section_type: :code,
               section_body: [
                 %{code: %{expr: ["i32.const": 1], locals: []}, size: 4},
                 %{code: %{expr: [return_call: 0], locals: []}, size: 4},
                 %{
                   code: %{
                     expr: ["i32.const": 0, return_call_indirect: %{table: 0, type: 0}],
                     locals: []
                   },
                   size: 7
                 }
               ]
             ]
    end

    test "wat: 17_names" do
      # Raw custom-section bytes depend on the wabt version - compare decoded
      # names and replace content with a marker before asserting.
      tree =
        parse_wat_sections("17_names")
        |> Enum.map(fn
          {:section_body, %{names: _} = body} ->
            {:section_body, Map.put(body, :content, :stripped)}

          kv ->
            kv
        end)

      assert tree == [
               section_type: :type,
               section_body: [{[:i32], [:i32]}],
               section_type: :function,
               section_body: [0],
               section_type: :memory,
               section_body: [{1, nil}],
               section_type: :global,
               section_body: [{{:i32, :const}, ["i32.const": 42]}],
               section_type: :code,
               section_body: [
                 %{
                   code: %{
                     expr: [
                       {:"local.get", 0},
                       {:"i32.const", 1},
                       :"i32.add",
                       {:"local.set", 1},
                       {:"local.get", 1}
                     ],
                     locals: [%{type: :i32, num: 1}]
                   },
                   size: 13
                 }
               ],
               section_type: :custom,
               section_body: %{
                 name: "name",
                 names: %{
                   module: "m",
                   fields: %{},
                   locals: %{0 => %{0 => "x", 1 => "y"}},
                   labels: %{},
                   types: %{},
                   funcs: %{0 => "add_one"},
                   tables: %{},
                   memories: %{0 => "mem"},
                   globals: %{0 => "answer"},
                   elems: %{},
                   datas: %{},
                   tags: %{}
                 },
                 content: :stripped
               }
             ]
    end

    test "wat: 5_int_factorial" do
      assert parse_wat_sections("5_int_factorial") == [
               section_type: :type,
               section_body: [{[:i32], [:i32]}],
               section_type: :function,
               section_body: [0],
               section_type: :export,
               section_body: [{"factorial", {:func, 0}}],
               section_type: :code,
               section_body: [
                 %{
                   code: %{
                     expr: [
                       "i32.const": 1,
                       "local.set": 1,
                       "i32.const": 1,
                       "local.set": 2,
                       block: %{
                         instr: [
                           loop: %{
                             instr: [
                               {:"local.get", 2},
                               {:"local.get", 0},
                               :"i32.gt_s",
                               {:br_if, 1},
                               {:"local.get", 1},
                               {:"local.get", 2},
                               :"i32.mul",
                               {:"local.set", 1},
                               {:"local.get", 2},
                               {:"i32.const", 1},
                               :"i32.add",
                               {:"local.set", 2},
                               {:br, 0}
                             ],
                             blocktype: :empty
                           }
                         ],
                         blocktype: :empty
                       },
                       "local.get": 1
                     ],
                     locals: [%{type: :i32, num: 2}]
                   },
                   size: 43
                 }
               ]
             ]
    end

    test "wat: 6_loop_sum" do
      assert parse_wat_sections("6_loop_sum") == [
               section_type: :type,
               section_body: [{[:i32], [:i32]}],
               section_type: :function,
               section_body: [0],
               section_type: :export,
               section_body: [{"sum_to", {:func, 0}}],
               section_type: :code,
               section_body: [
                 %{
                   code: %{
                     expr: [
                       block: %{
                         instr: [
                           loop: %{
                             instr: [
                               {:"local.get", 0},
                               {:"i32.const", 0},
                               :"i32.le_s",
                               {:br_if, 1},
                               {:"local.get", 1},
                               {:"local.get", 0},
                               :"i32.add",
                               {:"local.set", 1},
                               {:"local.get", 0},
                               {:"i32.const", 1},
                               :"i32.sub",
                               {:"local.set", 0},
                               {:br, 0}
                             ],
                             blocktype: :empty
                           }
                         ],
                         blocktype: :empty
                       },
                       "local.get": 1
                     ],
                     locals: [%{type: :i32, num: 1}]
                   },
                   size: 35
                 }
               ]
             ]
    end

    test "wat: 7_block_br" do
      assert parse_wat_sections("7_block_br") == [
               section_type: :type,
               section_body: [{[:i32], [:i32]}],
               section_type: :function,
               section_body: [0],
               section_type: :export,
               section_body: [{"nonneg_or_zero", {:func, 0}}],
               section_type: :code,
               section_body: [
                 %{
                   code: %{
                     expr: [
                       "local.get": 0,
                       "local.set": 1,
                       block: %{
                         instr: [
                           {:"local.get", 0},
                           {:"i32.const", 0},
                           :"i32.ge_s",
                           {:br_if, 0},
                           {:"i32.const", 0},
                           {:"local.set", 1}
                         ],
                         blocktype: :empty
                       },
                       "local.get": 1
                     ],
                     locals: [%{type: :i32, num: 1}]
                   },
                   size: 24
                 }
               ]
             ]
    end

    test "wat: 8_globals" do
      assert parse_wat_sections("8_globals") == [
               section_type: :global,
               section_body: [
                 {{:i32, :const}, ["i32.const": 42]},
                 {{:i32, :var}, ["i32.const": -7]}
               ]
             ]
    end

    test "wat: 18_exceptions" do
      assert parse_wat_sections("18_exceptions") == [
               section_type: :type,
               section_body: [{[:i32], []}, {[], []}, {[], [:i32]}],
               section_type: :function,
               section_body: [1, 2, 2],
               section_type: :tag,
               section_body: [tag: 0],
               section_type: :export,
               section_body: [{"typed", {:func, 1}}, {"any", {:func, 2}}],
               section_type: :code,
               section_body: [
                 %{code: %{expr: ["i32.const": 7, throw: 0], locals: []}, size: 6},
                 %{
                   code: %{
                     expr: [
                       block: %{
                         blocktype: :i32,
                         instr: [
                           try_table: %{
                             blocktype: :i32,
                             instr: [call: 0, "i32.const": 111],
                             catches: [{:catch, 0, 0}]
                           }
                         ]
                       }
                     ],
                     locals: []
                   },
                   size: 17
                 },
                 %{
                   code: %{
                     expr: [
                       block: %{
                         blocktype: :empty,
                         instr: [
                           try_table: %{
                             blocktype: :empty,
                             instr: [call: 0],
                             catches: [catch_all: 0]
                           }
                         ]
                       },
                       "i32.const": 999
                     ],
                     locals: []
                   },
                   size: 16
                 }
               ]
             ]
    end

    # wabt 1.0.41 cannot compile GC WAT, so GC instructions are exercised
    # through hand-built module bytes (the parser does not validate types,
    # so a dummy functype section is sufficient).
    test "GC instruction bytes parse end-to-end" do
      module =
        @header <>
          <<1, 4, 1, 0x60, 0, 0>> <>
          <<3, 2, 1, 0>> <>
          <<10, 17, 1, 15, 0>> <>
          <<0xFB, 0x00, 0x00>> <>
          <<0xFB, 0x0F>> <>
          <<0xFB, 0x02, 0x00, 0x00>> <>
          <<0xFB, 0x12, 0x00, 0x00>> <>
          <<0x0B>>

      sections =
        module
        |> parse_binary()
        |> Enum.filter(fn {k, _} -> k in [:section_type, :section_body] end)

      code_entry = %{
        code: %{
          locals: [],
          expr: [
            {:"struct.new", 0},
            :"array.len",
            {:"struct.get", %{type: 0, field: 0}},
            {:"array.init_data", %{type: 0, data: 0}}
          ]
        },
        size: 15
      }

      assert sections == [
               {:section_type, :type},
               {:section_body, [{[], []}]},
               {:section_type, :function},
               {:section_body, [0]},
               {:section_type, :code},
               {:section_body, [code_entry]}
             ]
    end

    test "wat: 20_simd" do
      assert parse_wat_sections("20_simd") == [
               section_type: :type,
               section_body: [{[:i32], [:i32]}],
               section_type: :function,
               section_body: [0],
               section_type: :memory,
               section_body: [{1, nil}],
               section_type: :export,
               section_body: [{"vops", {:func, 0}}],
               section_type: :code,
               section_body: [
                 %{
                   code: %{
                     expr: [
                       {:"i32.const", 0},
                       {:"v128.load", %{offset: 2, align: 4}},
                       {:"local.set", 1},
                       {:"local.get", 1},
                       {:"local.get", 0},
                       :"i32x4.splat",
                       :"i32x4.add",
                       {:"local.set", 1},
                       {:"local.get", 1},
                       {:"local.get", 1},
                       {:"i8x16.shuffle", [0, 15, 1, 14, 2, 13, 3, 12, 4, 11, 5, 10, 6, 9, 7, 8]},
                       :drop,
                       {:"local.get", 1},
                       :"f64x2.abs",
                       :drop,
                       {:"local.get", 1},
                       :"v128.any_true",
                       :drop,
                       {:"local.get", 1},
                       {:"i32x4.extract_lane", 0}
                     ],
                     locals: [%{type: :v128, num: 1}]
                   },
                   size: 62
                 }
               ]
             ]
    end

    test "wat: 21_atomics" do
      assert parse_wat_sections("21_atomics") == [
               section_type: :type,
               section_body: [{[], [:i32]}],
               section_type: :function,
               section_body: [0, 0, 0],
               section_type: :memory,
               section_body: [{1, 1, :shared}],
               section_type: :export,
               section_body: [
                 {"wait32", {:func, 0}},
                 {"load", {:func, 1}},
                 {"rmw", {:func, 2}}
               ],
               section_type: :code,
               section_body: [
                 %{
                   code: %{
                     expr: [
                       "i32.const": 0,
                       "i32.const": 0,
                       "i64.const": -1,
                       "memory.atomic.wait32": %{offset: 0, align: 2}
                     ],
                     locals: []
                   },
                   size: 12
                 },
                 %{
                   code: %{
                     expr: ["i32.const": 0, "i32.atomic.load": %{offset: 0, align: 2}],
                     locals: []
                   },
                   size: 8
                 },
                 %{
                   code: %{
                     expr: [
                       "i32.const": 0,
                       "i32.const": 1,
                       "i32.atomic.rmw.add": %{offset: 0, align: 2}
                     ],
                     locals: []
                   },
                   size: 10
                 }
               ]
             ]
    end

    test "prefix instruction tables resolve" do
      assert WaParser.PrefixInstrs.simd(0) == {:"v128.load", :memarg}
      assert WaParser.PrefixInstrs.simd(12) == {:"v128.const", :v128const}
      assert WaParser.PrefixInstrs.simd(35) == {:"i8x16.eq", :none}
      assert WaParser.PrefixInstrs.fe(0) == {:"memory.atomic.notify", :memarg}
      assert WaParser.PrefixInstrs.gc(0) == {:"struct.new", :type}
      assert WaParser.PrefixInstrs.gc(24) == {:br_on_cast, :cast}

      assert_raise WaParser.ParseError, ~r/sub-opcode/, fn ->
        WaParser.PrefixInstrs.gc(999)
      end
    end

    defp sec(id, payload), do: <<id, byte_size(payload)>> <> payload

    test "gc composite types: struct / rec / sub" do
      type_payload =
        <<1, 0x4E, 2>> <>
          <<0x50, 1, 0, 0x5E, 0x77, 1>> <>
          <<0x5E, 0x78, 0>>

      mod = @header <> sec(1, type_payload)

      assert mod
             |> parse_binary()
             |> Enum.filter(fn {k, _} -> k in [:section_type, :section_body] end) == [
               {:section_type, :type},
               {:section_body,
                [
                  %{
                    rec: [
                      %{
                        supers: [0],
                        final: false,
                        type: %{array: %{type: :i16, mut: :var}}
                      },
                      %{array: %{type: :i8, mut: :const}}
                    ]
                  }
                ]}
             ]
    end

    test "gc composite types: plain struct entry" do
      type_payload = <<1, 0x5F, 2, 0x7F, 1, 0x7E, 0>>
      mod = @header <> sec(1, type_payload)

      assert mod
             |> parse_binary()
             |> Enum.filter(fn {k, _} -> k in [:section_type, :section_body] end) == [
               {:section_type, :type},
               {:section_body,
                [%{struct: [%{type: :i32, mut: :var}, %{type: :i64, mut: :const}]}]}
             ]
    end

    test "typed reference global with ref.null initializer" do
      global_payload = <<1, 0x63, 0x70, 0, 0xD0, 0x70, 0x0B>>
      mod = @header <> sec(6, global_payload)

      assert mod
             |> parse_binary()
             |> Enum.filter(fn {k, _} -> k in [:section_type, :section_body] end) == [
               {:section_type, :global},
               {:section_body, [{{{:ref_null, :func}, :const}, ["ref.null": :func]}]}
             ]
    end

    test "i64 memory limits" do
      mem_payload = <<1, 0x05, 1, 2>>
      mod = @header <> sec(5, mem_payload)

      assert mod
             |> parse_binary()
             |> Enum.filter(fn {k, _} -> k in [:section_type, :section_body] end) == [
               {:section_type, :memory},
               {:section_body, [{1, 2, :i64}]}
             ]
    end

    test "tag import and export descriptors" do
      type_payload = <<1, 0x60, 1, 0x7F, 0>>

      import_payload =
        <<1>> <>
          <<3, "env"::binary, 1, "t"::binary, 0x04, 0x00, 0>>

      export_payload = <<1, 1, "t"::binary, 0x04, 0>>

      mod =
        @header <>
          sec(1, type_payload) <>
          sec(2, import_payload) <>
          sec(7, export_payload)

      assert mod
             |> parse_binary()
             |> Enum.filter(fn {k, _} -> k in [:section_type, :section_body] end) == [
               {:section_type, :type},
               {:section_body, [{[:i32], []}]},
               {:section_type, :import},
               {:section_body, [{"env", "t", {:tag, 0}}]},
               {:section_type, :export},
               {:section_body, [{"t", {:tag, 0}}]}
             ]
    end

    # -- compact import section proposal (markers 0x7F / 0x7E) ---------------
    # The import section's leading count is the TOTAL number of imports; a
    # compact entry shares a module name (0x7F) or module name + externtype
    # (0x7E) across several field names. All forms flatten to the same
    # {module, field, desc} list as the standard encoding.

    test "standard import form is unchanged (two imports)" do
      # count 2, both standard: env.a (func 0), env.b (func 1)
      import_payload =
        <<2, 3, "env", 1, "a", 0x00, 0, 3, "env", 1, "b", 0x00, 1>>

      type_payload = <<1, 0x60, 0, 0>>

      mod = @header <> sec(1, type_payload) <> sec(2, import_payload)

      assert mod
             |> parse_binary()
             |> Enum.filter(fn {k, _} -> k == :section_body end)
             |> Enum.at(1) ==
               {:section_body, [{"env", "a", {:func, 0}}, {"env", "b", {:func, 1}}]}
    end

    test "compact form A (0x7F): imports share a module name" do
      # total count 2; one compact entry: module wasi..., empty field, 0x7F,
      # inner count 2, items (environ_sizes_get, func 0) and (environ_get, func 0)
      import_payload =
        <<2, 22, "wasi_snapshot_preview1", 0, 0x7F, 2, 17, "environ_sizes_get", 0x00, 0, 11,
          "environ_get", 0x00, 0>>

      type_payload = <<1, 0x60, 0, 0>>

      mod = @header <> sec(1, type_payload) <> sec(2, import_payload)

      assert mod
             |> parse_binary()
             |> Enum.filter(fn {k, _} -> k == :section_body end)
             |> Enum.at(1) ==
               {:section_body,
                [
                  {"wasi_snapshot_preview1", "environ_sizes_get", {:func, 0}},
                  {"wasi_snapshot_preview1", "environ_get", {:func, 0}}
                ]}
    end

    test "compact form A with an empty item list contributes zero imports" do
      # total count 1: a compact form-A entry with inner count 0 (yields nothing),
      # followed by one standard import. The empty compact entry must be consumed
      # without producing an import or leaving trailing bytes.
      import_payload =
        <<1, 3, "env", 0, 0x7F, 0, 3, "env", 1, "a", 0x00, 0>>

      type_payload = <<1, 0x60, 0, 0>>

      mod = @header <> sec(1, type_payload) <> sec(2, import_payload)

      assert mod
             |> parse_binary()
             |> Enum.filter(fn {k, _} -> k == :section_body end)
             |> Enum.at(1) == {:section_body, [{"env", "a", {:func, 0}}]}
    end

    test "compact form B (0x7E): imports share a module name and externtype" do
      # total count 2; one compact entry: module env, empty field, 0x7E,
      # shared externtype func 0, inner count 2, names a and b
      import_payload = <<2, 3, "env", 0, 0x7E, 0x00, 0, 2, 1, "a", 1, "b">>
      type_payload = <<1, 0x60, 0, 0>>

      mod = @header <> sec(1, type_payload) <> sec(2, import_payload)

      assert mod
             |> parse_binary()
             |> Enum.filter(fn {k, _} -> k == :section_body end)
             |> Enum.at(1) ==
               {:section_body, [{"env", "a", {:func, 0}}, {"env", "b", {:func, 0}}]}
    end

    test "compact form B with an empty name list contributes zero imports" do
      # total count 1: a compact form-B entry with inner count 0 (yields nothing),
      # followed by one standard import. The empty compact entry must be consumed.
      import_payload =
        <<1, 3, "env", 0, 0x7E, 0x00, 0, 0, 3, "env", 1, "a", 0x00, 0>>

      type_payload = <<1, 0x60, 0, 0>>

      mod = @header <> sec(1, type_payload) <> sec(2, import_payload)

      assert mod
             |> parse_binary()
             |> Enum.filter(fn {k, _} -> k == :section_body end)
             |> Enum.at(1) == {:section_body, [{"env", "a", {:func, 0}}]}
    end

    test "an invalid importdesc tag raises a structured parse error" do
      # standard entry but the descriptor byte is 0x05 (not 0x00..0x04 nor a marker)
      import_payload = <<1, 3, "env", 1, "a", 0x05>>

      e =
        assert_raise WaParser.ParseError, fn ->
          parse_binary(@header <> sec(2, import_payload))
        end

      assert e.reason == :invalid_importdesc
    end

    test "a compact marker with a non-empty field name is malformed" do
      # 0x7F marker but the field name is "a" (non-empty)
      import_payload = <<1, 3, "env", 1, "a", 0x7F, 0>>

      e =
        assert_raise WaParser.ParseError, fn ->
          parse_binary(@header <> sec(2, import_payload))
        end

      assert e.reason == :malformed_compact_import
    end

    test "unknown opcode carries its hex byte" do
      # type ()->() | function [0] | code: count=1, size=3, locals=0, 0xFE, end
      module =
        @header <>
          <<1, 4, 1, 0x60, 0, 0>> <>
          <<3, 2, 1, 0>> <>
          <<10, 5, 1, 3, 0, 0xCC, 0x0B>>

      e =
        assert_raise WaParser.ParseError, fn ->
          parse_binary(module)
        end

      assert e.reason == :unknown_opcode
      assert e.detail =~ ~r/cc/i
    end
  end
end
