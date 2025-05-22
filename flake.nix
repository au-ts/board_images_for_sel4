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

        rpi4Aarch64Image = pkgs.runCommand "image-aarch64-rpi4" { nativeBuildInputs = with pkgs; [ mtools dosfstools util-linux ]; }
          ''
            mkdir -p $out/firmware

            dd if=/dev/zero of=$out/boot_part.img bs=1M count=64
            mkfs.vfat $out/boot_part.img

            cp ${rpi4Aarch64Uboot}/u-boot.bin $out
            cp ${rpiFirmware}/boot/start4.elf $out/firmware
            cp ${rpiFirmware}/boot/fixup4.dat $out/firmware
            cp ${rpiFirmware}/boot/bcm2711-rpi-4-b.dtb $out/firmware
            cp -r ${rpiFirmware}/boot/overlays $out/firmware/overlays

            mcopy -i $out/boot_part.img -s $out/firmware/* ${rpi4Aarch64Uboot}/u-boot.bin ${rpi4ConfigTxt}/config.txt ::

            dd if=/dev/zero of=$out/sd.img bs=1M count=128
            sfdisk --no-reread --no-tell-kernel $out/sd.img <<EOF
              label: dos

              start=2048,size=64M,type=b
            EOF
            dd if=$out/boot_part.img of=$out/sd.img conv=notrunc seek=2048
          ''
        ;

        maaxboardAarch64Image = pkgs.runCommand "maaxboard-aarch64-image" {}
          ''
            mkdir -p $out
            dd if=/dev/zero of=$out/sd.img bs=1M count=32
            dd if=${avnetImxMkimage}/flash.bin of=$out/sd.img conv=notrunc bs=1K seek=33
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

          nativeBuildInputs = with pkgs; [ musl zlib.dev zlib.static dtc ];

          makeFlags = [
            "CC=musl-gcc"
            "SOC=iMX8MQ"
            "flash_ddr4_val"
          ];

          hardeningDisable = ["all"];

          postPatch = ''
            patchShebangs scripts/
          '';

          preBuild = ''
            cp ${maaxboardAarch64Uboot}/u-boot-nodtb.bin iMX8M
            cp ${maaxboardAarch64Uboot}/u-boot-spl.bin iMX8M
            cp ${maaxboardAarch64Uboot}/maaxboard.dtb iMX8M/fsl-imx8mq-ddr4-arm2.dtb
            cp ${maaxboardAarch64Uboot}/mkimage iMX8M/mkimage_uboot

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

        maaxboardAarch64Uboot = pkgs.pkgsCross.aarch64-multiplatform.buildUBoot rec {
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

        rockpro64Aarch64Uboot = pkgs.pkgsCross.aarch64-multiplatform.buildUBoot rec {
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

        rockpro64Aarch64Image = pkgs.runCommand "rockpro64-aarch64-image" {}
          ''
            mkdir -p $out
            dd if=/dev/zero of=$out/sd.img bs=1M count=64
            dd if=${rockpro64Aarch64Uboot}/u-boot-rockchip.bin of=$out/sd.img conv=notrunc seek=64
          ''
        ;

        rpi4Aarch64Uboot = pkgs.pkgsCross.aarch64-multiplatform.buildUBoot rec {
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

        odroidc4Aarch64Uboot = pkgs.stdenv.mkDerivation rec {
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

        odroidc4Aarch64Image = pkgs.runCommand "odroidc4-aarch64-image" {}
          ''
            mkdir -p $out
            dd if=/dev/zero of=$out/sd.img bs=1M count=64
            dd if=${odroidc4Aarch64Uboot}/u-boot.bin.sd.bin of=$out/sd.img conv=notrunc bs=512 skip=1 seek=1
            dd if=${odroidc4Aarch64Uboot}/u-boot.bin.sd.bin of=$out/sd.img conv=notrunc bs=1 count=440
          ''
        ;

        star64Riscv64Uboot = pkgs.pkgsCross.riscv64.buildUBoot rec {
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

        star64Riscv64Image = pkgs.runCommand "star64-riscv64-image" { nativeBuildInputs = with pkgs; [ gptfdisk ]; }
          ''
            mkdir -p $out
            dd if=/dev/zero of=$out/sd.img bs=1M count=64
            sgdisk --clear \
              --set-alignment=2 \
              --new=1:4096:8191 --change-name=1:spl --typecode=1:2E54B353-1271-4842-806F-E436D6AF6985\
              --new=2:8192:16383 --change-name=2:uboot --typecode=2:BC13C2FF-59E6-4262-A352-B275FD6F7172  \
              $out/sd.img
            dd if=${star64Riscv64Uboot}/u-boot-spl.bin.normal.out of=$out/sd.img conv=notrunc seek=4096
            dd if=${star64Riscv64Uboot}/u-boot.itb of=$out/sd.img conv=notrunc seek=8192
          ''
        ;
      in
      {
        # All packages have the format <BOARD>-<ARCH>-<ARTIFACT>

        packages.star64-riscv64-uboot = star64Riscv64Uboot;
        packages.star64-riscv64-image = star64Riscv64Image;

        packages.maaxboard-aarch64-uboot = maaxboardAarch64Uboot;
        packages.maaxboard-aarch64-image = maaxboardAarch64Image;

        packages.odroidc4-aarch64-uboot = odroidc4Aarch64Uboot;
        packages.odroidc4-aarch64-image = odroidc4Aarch64Image;

        packages.rpi4-aarch64-uboot = rpi4Aarch64Uboot;
        packages.rpi4-aarch64-image = rpi4Aarch64Image;

        packages.rockpro64-aarch64-uboot = rockpro64Aarch64Uboot;
        packages.rockpro64-aarch64-image = rockpro64Aarch64Image;
      });
}
