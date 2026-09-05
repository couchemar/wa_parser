{
  description = "WASM Parser";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            cmake
            rebar3
            beamPackages.elixir
            ninja
            wabt
          ];
          ERL_INCLUDE_PATH = "${pkgs.beamPackages.erlang}/lib/erlang/usr/include";

          # wa_parser_ex builds against the sibling Erlang core in this
          # repo rather than the published hex release. The path points at
          # the repo root (which is the `wa_parser` rebar3 project).
          WA_PARSER_PATH = "..";
        };
      }
    );
}
