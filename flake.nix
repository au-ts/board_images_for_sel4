{
  description = "A flake for building flashable images for seL4 development";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
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
          # For ARM trusted firmware for RK3399 and potentially other future
          # platforms.
          config.allowUnfree = true;
        };

        ubootVersion = "v2024.10";
        mainlineUboot = pkgs.fetchFromGitHub {
          owner = "u-boot";
          repo = "u-boot";
          rev = ubootVersion;
          hash = "sha256-UPy7XM1NGjbEt+pQr4oQrzD7wWWEtYDOPWTD+CNYMHs=";
        };

        aarch64BuildUBoot = pkgs.pkgsCross.aarch64-multiplatform.buildUBoot;
        riscv64BuildUBoot = pkgs.pkgsCross.riscv64.buildUBoot;

        buildOpensbi = pkgs.pkgsCross.riscv64.opensbi;

        armTrustedFirmwareRK3399 = pkgs.pkgsCross.aarch64-multiplatform.armTrustedFirmwareRK3399;

        cheshire = pkgs.callPackage ./board/cheshire.nix {
          inherit buildOpensbi;
          buildUBoot = riscv64BuildUBoot;
          riscv64-embedded = pkgs.pkgsCross.riscv64-embedded;
        };

        hifive-p550 = pkgs.callPackage ./board/hifive-p550.nix {
          buildUBoot = riscv64BuildUBoot;
        };

        maaxboard = pkgs.callPackage ./board/maaxboard.nix {
          buildUBoot = aarch64BuildUBoot;
          aarch64-multiplatform = pkgs.pkgsCross.aarch64-multiplatform;
        };

        milkv-jupiter = pkgs.callPackage ./board/milkv-jupiter.nix {
          buildUBoot = riscv64BuildUBoot;
        };

        odroidc4 = pkgs.callPackage ./board/odroidc4.nix {
          buildUBoot = aarch64BuildUBoot;
          ubootSrc = mainlineUboot;
        };

        rockpro64 = pkgs.callPackage ./board/rockpro64.nix {
          inherit armTrustedFirmwareRK3399;
          buildUBoot = aarch64BuildUBoot;
          ubootSrc = mainlineUboot;
        };

        rpi4 = pkgs.callPackage ./board/rpi4b.nix {
          buildUBoot = aarch64BuildUBoot;
          ubootSrc = mainlineUboot;
        };

        rpi5 = pkgs.callPackage ./board/rpi5b.nix {
          buildUBoot = aarch64BuildUBoot;
        };

        star64 = pkgs.callPackage ./board/star64.nix {
          inherit buildOpensbi;
          buildUBoot = riscv64BuildUBoot;
          ubootSrc = mainlineUboot;
        };

        tx2 = pkgs.callPackage ./board/tx2.nix {
          buildUBoot = aarch64BuildUBoot;
          ubootSrc = mainlineUboot;
        };

        allImages = pkgs.runCommand "all-images" { nativeBuildInputs = with pkgs; [ gnutar gzip ]; }
          ''
            mkdir -p $out

            cp ${cheshire.image}/sd.img $out/cheshire-riscv64.img
            cp ${maaxboard.image}/sd.img $out/maaxboard-aarch64.img
            cp ${odroidc4.image}/sd.img $out/odroidc4-aarch64.img
            cp ${rpi4.image}/sd.img $out/rpi4-aarch64.img
            cp ${rockpro64.image}/sd.img $out/rockpro64-aarch64.img
            cp ${rpi5.image}/sd.img $out/rpi5-aarch64.img
            cp ${star64.image}/sd.img $out/star64-riscv64.img

            cd $out
            for f in *.img; do tar cf - $f | gzip -9 > `basename $f`.tar.gz; done
          ''
        ;
      in
      {
        # All packages have the format <BOARD>-<ARCH>-<ARTIFACT>

        packages.maaxboard-aarch64-uboot = maaxboard.ubooot;
        packages.maaxboard-aarch64-image = maaxboard.image;

        packages.odroidc4-aarch64-uboot = odroidc4.uboot;
        packages.odroidc4-aarch64-image = odroidc4.image;

        packages.rpi4-aarch64-uboot = rpi4.uboot;
        packages.rpi4-aarch64-image = rpi4.image;

        packages.rpi5-aarch64-uboot = rpi5.uboot;
        packages.rpi5-aarch64-image = rpi5.image;

        packages.rockpro64-aarch64-uboot = rockpro64.uboot;
        packages.rockpro64-aarch64-image = rockpro64.image;

        packages.star64-riscv64-uboot = star64.uboot;
        packages.star64-riscv64-image = star64.image;

        packages.hifive-p550-riscv64-uboot = hifive-p550.uboot;

        packages.milkv-jupiter-riscv64-uboot = milkv-jupiter.uboot;

        packages.tx2-aarch64-uboot = tx2.uboot;

        packages.cheshire-riscv64-sw = cheshire.sw;
        packages.cheshire-riscv64-opensbi = cheshire.opensbi;
        packages.cheshire-riscv64-uboot = cheshire.uboot;
        packages.cheshire-riscv64-image = cheshire.image;

        packages.default = allImages;
      });
}
