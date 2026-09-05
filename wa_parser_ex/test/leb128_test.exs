defmodule LEB128Test do
  use ExUnit.Case

  test "Encode unsigned" do
    assert WaParser.LEB128.encode_unsigned(0) == <<0x00>>
    assert WaParser.LEB128.encode_unsigned(42) == <<0x2A>>
    assert WaParser.LEB128.encode_unsigned(624_485) == <<0xE5, 0x8E, 0x26>>
  end

  test "Decode unsigned" do
    assert WaParser.LEB128.decode_unsigned(<<0x00>>) == 0
    assert WaParser.LEB128.decode_unsigned(<<0x2A>>) == 42
    assert WaParser.LEB128.decode_unsigned(<<0xE5, 0x8E, 0x26>>) == 624_485
  end

  test "Encode signed" do
    assert WaParser.LEB128.encode_signed(0) == <<0x00>>
    assert WaParser.LEB128.encode_signed(123_456) == <<0xC0, 0xC4, 0x07>>
    assert WaParser.LEB128.encode_signed(-123_456) == <<0xC0, 0xBB, 0x78>>
  end

  test "Decode signed" do
    assert WaParser.LEB128.decode_signed(<<0x00>>) == 0
    assert WaParser.LEB128.decode_signed(<<0xC0, 0xC4, 0x07>>) == 123_456
    assert WaParser.LEB128.decode_signed(<<0xC0, 0xBB, 0x78>>) == -123_456
  end
end
