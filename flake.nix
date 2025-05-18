{
  description = "A flake for building flashable images for seL4 development";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, ... }@inputs: inputs.utils.lib.eachSystem [
    "x86_64-linux"
    "aarch64-linux"
  ]
    (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        ubootVersion = "v2024.10";
        mainlineUboot = pkgs.fetchFromGitHub {
          owner = "u-boot";
          repo = "u-boot";
          rev = ubootVersion;
          hash = "sha256-UPy7XM1NGjbEt+pQr4oQrzD7wWWEtYDOPWTD+CNYMHs=";
        };

        opensbi-riscv64-pine64-star64 = pkgs.pkgsCross.riscv64.callPackage ./opensbi.nix {
          extraMakeFlags = [
            "FW_TEXT_START=0x40000000"
          ];
        };

        disk = writeShellApplication {
          name = "make-disk";
          runtimeInputs = [ coreutils ];
          text = ''
            dd if=/dev/null of=$out/disk.img bs=1M count=16
          '';
        }
      in
      {
        packages.disk = disk;
        packages.uboot-riscv64-pine64-star64 = pkgs.pkgsCross.riscv64.buildUBoot rec {
            inherit opensbi-riscv64-pine64-star64;

            extraMeta.platforms = [ "riscv64-linux" ];
            version = ubootVersion;
            defconfig = "starfive_visionfive2_defconfig";

            extraMakeFlags = [
              "OPENSBI=${opensbi-riscv64-pine64-star64}/share/opensbi/lp64/generic/firmware/fw_dynamic.bin"
            ];

            filesToInstall = [
              "spl/u-boot-spl.bin.normal.out"
              "u-boot.itb"
            ];
            src = mainlineUboot;
        };

        packages.uboot-aarch64-odroidc4 = pkgs.pkgsCross.aarch64-multiplatform.buildUBoot rec {
            extraMeta.platforms = [ "aarch64-linux" ];
            version = ubootVersion;
            defconfig = "odroid-c4_defconfig";
            filesToInstall = [
              "u-boot.bin"
            ];
            src = mainlineUboot;
          };
      });
}
