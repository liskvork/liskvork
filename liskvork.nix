{
  lib,
  stdenv,
  zig,
  callPackage,
}:
stdenv.mkDerivation {
  pname = "liskvork";
  version = "0.0.0-dev";

  env.XDG_CACHE_HOME = "${placeholder "out"}";

  src = lib.cleanSource ./.;
  nativeBuildInputs = [zig.hook];

  postPatch = ''
    ln -s ${callPackage ./build.zig.zon.nix {}} $ZIG_GLOBAL_CACHE_DIR/p
  '';

  meta = {
    description = "Modern multi-platform gomoku game server";
    homepage = "liskvork.org";
    license = with lib.licenses; [eupl12];
    mainProgram = "liskvork";
  };
}
