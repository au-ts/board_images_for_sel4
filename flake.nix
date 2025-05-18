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

        amlogicBootFip = pkgs.fetchFromGitHub {
          owner = "LibreELEC";
          repo = "amlogic-boot-fip";
          # No particular reason for this commit other than it is a known working version.
          rev = "0312a79cc65bf7bb3d66d33ad0660b66146bd36d";
          hash = "sha256-6EIXP1g9LPYNz5jYYrY7PKeVbwSI3DeJBo5ZK17ePMg=";
        };

        rpiFirmware = pkgs.fetchFromGitHub {
          owner = "raspberrypi";
          repo = "firmware";
          rev = "1.20250430";
          hash = "sha256-U41EgEDny1R+JFktSC/3CE+2Qi7GJludj929ft49Nm0=";
        };

        imageAarch64Rpi4 = pkgs.runCommand "image-aarch64-rpi4" {}
          ''
            mkdir -p $out/firmware
            cp ${rpiFirmware}/boot/start4.elf $out/firmware
            cp ${rpiFirmware}/boot/fixup4.dat $out/firmware
            cp ${rpiFirmware}/boot/bcm2711-rpi-4-b.dtb $out/firmware
            cp -r ${rpiFirmware}/boot/overlays $out/firmware/overlays
          ''
        ;

        ubootAarch64Rockpro64 = pkgs.pkgsCross.aarch64-multiplatform.buildUBoot rec {
          extraMeta.platforms = [ "aarch64-linux" ];
          version = ubootVersion;
          defconfig = "rockpro64-rk3399_defconfig";
          BL31= "${pkgs.pkgsCross.aarch64-multiplatform.armTrustedFirmwareRK3399}/bl31.elf";
          filesToInstall = [
            "u-boot.bin"
          ];
          src = mainlineUboot;
        };

        ubootAarch64Rpi4 = pkgs.pkgsCross.aarch64-multiplatform.buildUBoot rec {
          extraMeta.platforms = [ "aarch64-linux" ];
          version = ubootVersion;
          defconfig = "rpi_4_defconfig";
          filesToInstall = [
            "u-boot.bin"
          ];
          src = mainlineUboot;
        };

        ubootAarch64Odroidc4 = pkgs.pkgsCross.aarch64-multiplatform.buildUBoot rec {
          extraMeta.platforms = [ "aarch64-linux" ];
          version = ubootVersion;
          defconfig = "odroid-c4_defconfig";
          # The defconfig does not setup 'saveenv' to work properly, so we do that here.
          extraConfing = ''
            CONFIG_ENV_IS_NOWHERE=n
            CONFIG_ENV_IS_IN_MMC=y
            CONFIG_ENV_OFFSET=0x10000000
          '';
          filesToInstall = [
            "u-boot.bin"
          ];
          src = mainlineUboot;
        };

        imageAarch64Odroidc4 = pkgs.runCommand "image-aarch64-odroidc4" {}
          ''
            mkdir -p $out/amlogic-boot-fip
            cd ${./amlogic-boot-fip}
            ./build-fip.sh odroid-c4 ${ubootAarch64Odroidc4.outPath}/u-boot.bin $out/amlogic-boot-fip
          ''
        ;
      in
      {
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

        packages.uboot-aarch64-odroidc4 = ubootAarch64Odroidc4;
        packages.image-aarch64-odroidc4 = imageAarch64Odroidc4;

        packages.uboot-aarch64-rpi4 = ubootAarch64Rpi4;
        packages.image-aarch64-rpi4 = imageAarch64Rpi4;

        packages.uboot-aarch64-rockpro64 = ubootAarch64Rockpro64;
      });
}
