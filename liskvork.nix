{
  lib,
  stdenv,
  zig_0_16,
  callPackage,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "liskvork";
  version = "0.0.0-dev";

  # env.XDG_CACHE_HOME = "${placeholder "out"}";

  src = lib.cleanSource ./.;
  nativeBuildInputs = [zig_0_16];

  deps = callPackage ./build.zig.zon.nix {};

  zigBuildFlags = [
    "--system"
    "${finalAttrs.deps}"
  ];

  meta = {
    description = "Modern multi-platform gomoku game server";
    homepage = "liskvork.org";
    license = with lib.licenses; [eupl12];
    mainProgram = "liskvork";
  };
})
