# Builds all test fixtures (C -> clang/llc/wasm-ld, WAT -> wat2wasm) through
# CMake/Ninja before the suite runs. Configure happens once; ninja is incremental.
fixture_dir = Path.expand("../../test_data", __DIR__)
build_dir = Path.join(fixture_dir, "build")

for tool <- ["cmake", "ninja"] do
  System.find_executable(tool) ||
    raise "#{tool} not found on PATH - enter the Nix shell first (`nix develop`)"
end

unless File.exists?(Path.join(build_dir, "build.ninja")) do
  case System.cmd("cmake", ["-S", fixture_dir, "-B", build_dir, "-G", "Ninja"],
         stderr_to_stdout: true
       ) do
    {_, 0} ->
      :ok

    {output, code} ->
      raise "cmake configure failed for test fixtures (exit #{code}):\n#{output}"
  end
end

case System.cmd("ninja", ["-C", build_dir], stderr_to_stdout: true) do
  {_, 0} ->
    :ok

  {output, code} ->
    raise "ninja failed building test fixtures (exit #{code}):\n#{output}"
end

ExUnit.start()
