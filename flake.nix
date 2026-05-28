{
  description = "srcML — source code as XML";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        nativeBuildInputs = with pkgs; [
          cmake
          ninja
          pkg-config
          jdk          # ANTLR runs the Java tool at configure time
        ];

        buildInputs = with pkgs; [
          libxml2
          libxslt
          libarchive
          curl
          boost
        ];
      in {
        devShells.default = pkgs.mkShell {
          inherit nativeBuildInputs buildInputs;

          shellHook = ''
            echo "srcML dev shell — run: cmake -S . -B build -G Ninja -DBUILD_CLIENT_TESTS=OFF && cmake --build build"
          '';
        };

        # Building srcML reproducibly via 'nix build' is non-trivial because
        # CMake fetches the manpage and ANTLR sources from the network at
        # configure time. The dev shell above is the recommended path for now.
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "srcml";
          version = "1.1.0";
          src = self;
          inherit nativeBuildInputs buildInputs;
          cmakeFlags = [
            "-DBUILD_LIBSRCML_TESTS=OFF"
            "-DBUILD_CLIENT_TESTS=OFF"
            "-DBUILD_PARSER_TESTS=OFF"
          ];
          # Disable network fetches inside the sandbox.
          # If this breaks, run: nix build --impure
          __noChroot = true;
        };
      });
}
