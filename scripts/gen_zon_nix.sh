#!/usr/bin/env sh

# This script is used to generate the build.zig.zon.nix at the root of the repo
# It will not generate a file that respects the nix formatter
# TODO: Generate according to the nix formatter

# Use it as follow:
# ./scripts/gen_zon_nix.sh > build.zig.zon.nix

nix run github:emneo-dev/zon2nix
