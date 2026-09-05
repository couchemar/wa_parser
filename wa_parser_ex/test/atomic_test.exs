defmodule AtomicTest do
  use ExUnit.Case

  alias WaParser.Types.Atomic
  import Bitwise

  # s33 = signed LEB128 used for blocktype type indices.
  # Spec range is [-2^32, 2^32 - 1]; indices below 64 encode as one byte.
  test "s33 decodes zero" do
    assert Atomic.s33(<<0x00, "rest">>) == {0, "rest"}
  end

  test "s33 decodes positive single byte" do
    assert Atomic.s33(<<0x01>>) == {1, ""}
    assert Atomic.s33(<<0x3F>>) == {63, ""}
  end

  test "s33 sign-extends single byte" do
    assert Atomic.s33(<<0x7F>>) == {-1, ""}
    assert Atomic.s33(<<0x40>>) == {-64, ""}
  end

  test "s33 decodes multi-byte values" do
    assert Atomic.s33(<<0x80, 0x01>>) == {128, ""}
    assert Atomic.s33(<<0xE5, 0x8E, 0x26>>) == {624_485, ""}
  end

  test "s33 decodes redundant multi-byte encodings" do
    # All-ones groups keep sign-extending to the same negative value.
    assert Atomic.s33(<<0xFF, 0x7F>>) == {-1, ""}
    assert Atomic.s33(<<0xC0, 0x7F>>) == {-64, ""}
  end

  test "s33 returns remaining binary" do
    assert Atomic.s33(<<0x02, 0xCA, 0xFE>>) == {2, <<0xCA, 0xFE>>}
  end

  # Property test: s33 roundtrip via LEB128 encode/decode.
  # Generates random signed integers in the s33 range, encodes as LEB128,
  # appends trailing bytes, and verifies Atomic.s33/1 recovers the original value.
  test "s33 roundtrip: encode then decode recovers the original value" do
    trailer = <<0xDE, 0xAD>>

    for _ <- 1..200 do
      value = random_s33_value()
      encoded = encode_signed_leb128(value)
      input = encoded <> trailer

      assert {^value, ^trailer} = Atomic.s33(input)
    end
  end

  test "s33 roundtrip: negative type indices" do
    trailer = <<0xFF>>

    # Negative type indices used in blocktype (e.g. -1 for i32, -2 for i64, etc.)
    for value <- [-1, -2, -3, -4, -64, -100, -1000, -100_000] do
      encoded = encode_signed_leb128(value)
      input = encoded <> trailer

      assert {^value, ^trailer} = Atomic.s33(input)
    end
  end

  defp random_s33_value do
    # s33 range: [-2^32, 2^32 - 1]
    max = :erlang.bsl(1, 32) - 1
    min = -:erlang.bsl(1, 32)
    min + :rand.uniform(max - min + 1) - 1
  end

  # Reference LEB128 signed encoder for testing (standard algorithm from the spec).
  defp encode_signed_leb128(value) do
    encode_signed_leb128(value, <<>>)
  end

  defp encode_signed_leb128(value, acc) do
    byte = value |> band(0x7F)
    value = bsr(value, 7)

    if (value == 0 and band(byte, 0x40) == 0) or
         (value == -1 and band(byte, 0x40) != 0) do
      acc <> <<byte>>
    else
      (acc <> <<bor(byte, 0x80)>>) |> encode_signed_leb128_cont(value)
    end
  end

  defp encode_signed_leb128_cont(acc, value) do
    byte = value |> band(0x7F)
    value = bsr(value, 7)

    if (value == 0 and band(byte, 0x40) == 0) or
         (value == -1 and band(byte, 0x40) != 0) do
      acc <> <<byte>>
    else
      (acc <> <<bor(byte, 0x80)>>) |> encode_signed_leb128_cont(value)
    end
  end

  # -- Width / canonicality enforcement -----------------------------------

  test "u32 rejects encodings longer than 5 bytes" do
    assert_raise WaParser.ParseError, ~r/non_canonical/, fn ->
      Atomic.u32(<<0x81, 0x81, 0x81, 0x81, 0x81, 0x01>>)
    end
  end

  test "u32 rejects set bits beyond the 32-bit payload" do
    # Terminal byte carries 4 payload bits; 0x10 has bit 4 set.
    assert_raise WaParser.ParseError, ~r/non_canonical/, fn ->
      Atomic.u32(<<0x80, 0x80, 0x80, 0x80, 0x10>>)
    end
  end

  test "u32 accepts terminal byte with zero padding" do
    assert Atomic.u32(<<0x80, 0x80, 0x80, 0x80, 0x00>>) == {0, ""}
  end

  test "i32 rejects padding that does not replicate the sign bit" do
    # rem = 4 payload bits (1111, sign 1) but padding bits are 000.
    assert_raise WaParser.ParseError, ~r/non_canonical/, fn ->
      Atomic.i32(<<0x80, 0x80, 0x80, 0x80, 0x0F>>)
    end
  end

  test "i32 accepts sign-replicated padding" do
    # 28 zero payload bits + terminal 1111 (sign 1, padding 111):
    # the legal encoding of -2^28.
    assert Atomic.i32(<<0x80, 0x80, 0x80, 0x80, 0x7F>>) == {-268_435_456, ""}
  end

  # Terminal payload 11011 (rem = 5): padding bits 10 do not replicate
  # the sign bit 1, so this claims a value beyond the 33-bit range.
  test "s33 rejects values beyond the 33-bit range" do
    assert_raise WaParser.ParseError, ~r/non_canonical/, fn ->
      Atomic.s33(<<0xFF, 0xFF, 0xFF, 0xFF, 0x5B>>)
    end
  end

  test "decoders raise on truncated sequences" do
    assert_raise WaParser.ParseError, ~r/truncated/, fn -> Atomic.u32(<<0x80>>) end
    assert_raise WaParser.ParseError, ~r/truncated/, fn -> Atomic.s33(<<>>) end
    assert_raise WaParser.ParseError, ~r/truncated/, fn -> Atomic.f64(<<1, 2, 3>>) end
  end
end
