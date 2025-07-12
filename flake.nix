{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    pre-commit-hooks,
  }: let
    forAllSystems = function:
      nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
        "aarch64-linux"
      ] (system: function nixpkgs.legacyPackages.${system});
  in {
    formatter = forAllSystems (pkgs: pkgs.alejandra);

    checks = forAllSystems (pkgs: let
      inherit (pkgs) lib system;

      hooks = {
        alejandra.enable = true;
        check-merge-conflicts.enable = true;
        check-shebang-scripts-are-executable.enable = true;
        check-added-large-files.enable = true;
        zig-fmt = {
          enable = true;
          entry = "${lib.getExe pkgs.zig} fmt --check .";
          files = "\\.z(ig|on)$";
        };
      };
    in {
      pre-commit-check = pre-commit-hooks.lib.${system}.run {
        inherit hooks;
        src = ./.;
      };
    });

    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        inherit (self.checks.${pkgs.system}.pre-commit-check) shellHook;

        name = "liskvork";
        inputsFrom = pkgs.lib.attrsets.attrValues self.packages.${pkgs.system};
        packages = with pkgs; [
          zls
        ];
      };
    });

    packages = forAllSystems (pkgs: {
      default = self.packages.${pkgs.system}.liskvork;

      liskvork = pkgs.callPackage ./liskvork.nix {};
    });
  };
}
