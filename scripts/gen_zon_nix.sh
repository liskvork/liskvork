#! /usr/bin/env nix-shell
#! nix-shell -i bash coreutils zon2nix -p bash

zon2nix \
  | nix --extra-experimental-features "nix-command flakes" fmt 2>/dev/null \
  | tee build.zig.zon.nix
