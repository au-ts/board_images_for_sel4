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

        opensbi-riscv64-pine64-star64 = pkgs.pkgsCross.riscv64.opensbi.overrideAttrs (oldattrs: {
          makeFlags = [
            "FW_TEXT_START=0x40000000"
          ] ++ oldattrs.makeFlags;
        });

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

        rpi4ConfigTxt = pkgs.writeTextFile {
          name = "config.txt";
          destination = "/config.txt";
          text = ''
            enable_uart=1
            arm_64bit=1
            kernel=u-boot.bin
          '';
        };

        imageAarch64Rpi4 = pkgs.runCommand "image-aarch64-rpi4" { nativeBuildInputs = with pkgs; [ mtools dosfstools util-linux ]; }
          ''
            mkdir -p $out/firmware

            dd if=/dev/zero of=$out/boot_part.img bs=1M count=64
            mkfs.vfat $out/boot_part.img

            cp ${ubootAarch64Rpi4}/u-boot.bin $out
            cp ${rpiFirmware}/boot/start4.elf $out/firmware
            cp ${rpiFirmware}/boot/fixup4.dat $out/firmware
            cp ${rpiFirmware}/boot/bcm2711-rpi-4-b.dtb $out/firmware
            cp -r ${rpiFirmware}/boot/overlays $out/firmware/overlays

            mcopy -i $out/boot_part.img -s $out/firmware/* ${ubootAarch64Rpi4}/u-boot.bin ${rpi4ConfigTxt}/config.txt ::

            dd if=/dev/zero of=$out/sd.img bs=1M count=128
            sfdisk --no-reread --no-tell-kernel $out/sd.img <<EOF
              label: dos

              start=2048,size=64M,type=b
            EOF
            dd if=$out/boot_part.img of=$out/sd.img conv=notrunc seek=2048
          ''
        ;

        avnetImxMkimage = pkgs.stdenv.mkDerivation rec {
          name = "avnet-imx-mkimage";
          src = pkgs.fetchFromGitHub {
            owner = "Avnet";
            repo = "imx-mkimage";
            rev = "develop_imx_4.14.78_1.0.0_ga";
            hash = "sha256-GTfbwkFXGbNoy/QbGyZS2VkL9OMBIvRxck3bFbopu50=";
          };

          nativeBuildInputs = with pkgs; [ musl zlib.static dtc ];

          makeFlags = [
            "CC=musl-gcc"
            "SOC=iMX8MQ"
            "flash_ddr4_val"
          ];

          # TODO: get rid of this patch
          patches = [ ./imx-mkimage-patch ];
          hardeningDisable = ["all"];

          postPatch = ''
            patchShebangs scripts/
          '';

          preBuild = ''
            cp ${ubootAarch64Maaxboard}/u-boot-nodtb.bin iMX8M
            cp ${ubootAarch64Maaxboard}/u-boot-spl.bin iMX8M
            cp ${ubootAarch64Maaxboard}/maaxboard.dtb iMX8M/fsl-imx8mq-ddr4-arm2.dtb
            cp ${ubootAarch64Maaxboard}/mkimage iMX8M/mkimage_uboot

            cp ${avnetImxAtf}/bl31.bin iMX8M/

            cp ${avnetImxFirmware}/ddr4_dmem_1d_202006.bin iMX8M/ddr4_dmem_1d.bin
            cp ${avnetImxFirmware}/ddr4_dmem_2d_202006.bin iMX8M/ddr4_dmem_2d.bin
            cp ${avnetImxFirmware}/ddr4_imem_1d_202006.bin iMX8M/ddr4_imem_1d.bin
            cp ${avnetImxFirmware}/ddr4_imem_2d_202006.bin iMX8M/ddr4_imem_2d.bin
            cp ${avnetImxFirmware}/signed_hdmi_imx8m.bin iMX8M/
          '';

          installPhase = ''
            mkdir -p $out
            cp iMX8M/flash.bin $out/
          '';
        };

        avnetImxAtf = pkgs.stdenv.mkDerivation rec {
          name = "avnet-imx-atf";
          src = pkgs.fetchFromGitHub {
            owner = "Avnet";
            repo = "imx-atf";
            rev = "maaxboard-imx_5.4.24_2.1.0";
            hash = "sha256-pDueidAeGysIj0R12NdqKBuZN/f7sCqjH1Kz8BWoYa4=";
          };

          nativeBuildInputs = [ pkgs.pkgsCross.aarch64-multiplatform.stdenv.cc ];

          makeFlags = [
            "CROSS_COMPILE=${pkgs.pkgsCross.aarch64-multiplatform.stdenv.cc.targetPrefix}"
            "PLAT=imx8mq"
          ];

          hardeningDisable = ["all"];

          prePatch = ''
            echo "TF_LDFLAGS += --no-warn-rwx-segments" >> Makefile
            echo "TF_CFLAGS_aarch64 += --param=min-pagesize=0" >> Makefile
          '';

          installPhase = ''
            mkdir -p $out
            cp build/imx8mq/release/bl31.bin $out
          '';
        };

        avnetImxFirmware = pkgs.pkgsCross.aarch64-multiplatform.stdenv.mkDerivation rec {
          name = "avnet-imx-firmware";
          src = pkgs.fetchurl {
            url = "https://sources.buildroot.net/firmware-imx/firmware-imx-8.22.bin";
            hash = "sha256-lMi86sVuxQPCMuYU931rvY4Xx9qnHU5lHqj9UDTDA1A=";
          };
          dontUnpack = true;

          buildPhase = ''
            bash ${src} --auto-accept
          '';

          installPhase = ''
            mkdir -p $out
            cp firmware-imx-8.22/firmware/ddr/synopsys/ddr4_dmem_1d_202006.bin $out
            cp firmware-imx-8.22/firmware/ddr/synopsys/ddr4_dmem_2d_202006.bin $out
            cp firmware-imx-8.22/firmware/ddr/synopsys/ddr4_imem_1d_202006.bin $out
            cp firmware-imx-8.22/firmware/ddr/synopsys/ddr4_imem_2d_202006.bin $out
            cp firmware-imx-8.22/firmware/hdmi/cadence/signed_hdmi_imx8m.bin $out
          '';
        };

        ubootAarch64Maaxboard = pkgs.pkgsCross.aarch64-multiplatform.buildUBoot rec {
          extraMeta.platforms = [ "aarch64-linux" ];
          # There are multiple branches that could work on the Avnet fork of U-Boot. This one
          # was chosen as it is known to work.
          version = "maaxboard_v2021.04_5.10.35_2.0.0";
          defconfig = "maaxboard_defconfig";
          filesToInstall = [
            "u-boot.bin"
            "arch/arm/dts/maaxboard.dtb"
            "spl/u-boot-spl.bin"
            "tools/mkimage"
            "u-boot-nodtb.bin"
          ];
          # Nix buildUBoot tries to apply Rasbperry Pi specific patches to the source
          # which doesn't work for forks.
          dontPatch = true;
          src = pkgs.fetchFromGitHub {
            owner = "Avnet";
            repo = "uboot-imx";
            rev = version;
            hash = "sha256-IuMaAmS2jyckLq4+vTwZaf1H0foh7DwicV5vrDKDC9M=";
          };
        };

        ubootAarch64Rockpro64 = pkgs.pkgsCross.aarch64-multiplatform.buildUBoot rec {
          extraMeta.platforms = [ "aarch64-linux" ];
          version = ubootVersion;
          defconfig = "rockpro64-rk3399_defconfig";
          BL31 = "${pkgs.pkgsCross.aarch64-multiplatform.armTrustedFirmwareRK3399}/bl31.elf";
          filesToInstall = [
            "u-boot-rockchip.bin"
            "u-boot.bin"
            "u-boot.itb"
            "idbloader.img"
          ];
          src = mainlineUboot;
        };

        rockpro64Image = pkgs.runCommand "star64-riscv64-image" {}
          ''
            mkdir -p $out
            dd if=/dev/zero of=$out/sd.img bs=1M count=64
            dd if=${ubootAarch64Rockpro64}/u-boot-rockchip.bin of=$out/sd.img conv=notrunc seek=64
          ''
        ;

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

        imageAarch64Odroidc4 = pkgs.stdenv.mkDerivation rec {
          name = "image-aarch64-odroidc4";
          src = pkgs.fetchFromGitHub {
            owner = "LibreELEC";
            repo = "amlogic-boot-fip";
            # No particular reason for this commit other than it is a known working version.
            rev = "0312a79cc65bf7bb3d66d33ad0660b66146bd36d";
            hash = "sha256-6EIXP1g9LPYNz5jYYrY7PKeVbwSI3DeJBo5ZK17ePMg=";
          };

          buildPhase = ''
            mkdir -p $out
            patchShebangs odroid-c4/blx_fix.sh
            bash ./build-fip.sh odroid-c4 ${ubootAarch64Odroidc4.outPath}/u-boot.bin $out
          ''
          ;
        };

        uBootRiscv64Star64 = pkgs.pkgsCross.riscv64.buildUBoot rec {
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

        star64Image = pkgs.runCommand "star64-riscv64-image" { nativeBuildInputs = with pkgs; [ gptfdisk ]; }
          ''
            mkdir -p $out
            dd if=/dev/zero of=$out/sd.img bs=1M count=64
            sgdisk --clear \
              --set-alignment=2 \
              --new=1:4096:8191 --change-name=1:spl --typecode=1:2E54B353-1271-4842-806F-E436D6AF6985\
              --new=2:8192:16383 --change-name=2:uboot --typecode=2:BC13C2FF-59E6-4262-A352-B275FD6F7172  \
              $out/sd.img
            dd if=${uBootRiscv64Star64}/u-boot-spl.bin.normal.out of=$out/sd.img conv=notrunc seek=4096
            dd if=${uBootRiscv64Star64}/u-boot.itb of=$out/sd.img conv=notrunc seek=8192
          ''
        ;
      in
      {
        packages.star64-riscv64-uboot = uBootRiscv64Star64;
        packages.star64-riscv64-image = star64Image;

        packages.avnet-imx-firmware = avnetImxFirmware;
        packages.avnet-imx-atf = avnetImxAtf;
        packages.avnet-imx-mkimage = avnetImxMkimage;
        packages.maaxboard-uboot-aarch64 = ubootAarch64Maaxboard;
        packages.maaxboard-image-aarch64 = avnetImxMkimage;

        packages.odroidc4-uboot-aarch64 = ubootAarch64Odroidc4;
        packages.odroidc4-image-microsd-aarch64 = imageAarch64Odroidc4;

        packages.rpi4-uboot-aarch64 = ubootAarch64Rpi4;
        packages.rpi4-image-aarch64 = imageAarch64Rpi4;

        packages.rockpro64-uboot-aarch64 = ubootAarch64Rockpro64;
        packages.rockpro64-image-aarch64 = rockpro64Image;
      });
}
