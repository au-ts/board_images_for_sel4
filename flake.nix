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

        rpi5ConfigTxt = pkgs.writeTextFile {
          name = "config.txt";
          destination = "/config.txt";
          text = ''
            [all]
            enable_uart=1
            uart_2ndstage=1
            arm_64bit=1
            kernel=u-boot.bin
          '';
        };

        rpi5Aarch64Image = pkgs.runCommand "image-aarch64-rpi5" { nativeBuildInputs = with pkgs; [ mtools dosfstools util-linux ]; }
          ''
            mkdir -p $out/firmware

            dd if=/dev/zero of=$out/boot_part.img bs=1M count=64
            mkfs.vfat $out/boot_part.img

            cp ${rpi5Aarch64Uboot}/u-boot.bin $out
            cp ${rpiFirmware}/boot/start4.elf $out/firmware
            cp ${rpiFirmware}/boot/fixup4.dat $out/firmware
            cp ${rpiFirmware}/boot/bcm2712-rpi-5-b.dtb $out/firmware
            cp -r ${rpiFirmware}/boot/overlays $out/firmware/overlays

            mcopy -i $out/boot_part.img -s $out/firmware/* ${rpi5Aarch64Uboot}/u-boot.bin ${rpi5ConfigTxt}/config.txt ::

            dd if=/dev/zero of=$out/sd.img bs=1M count=128
            sfdisk --no-reread --no-tell-kernel $out/sd.img <<EOF
              label: dos

              start=2048,size=64M,type=b
            EOF
            dd if=$out/boot_part.img of=$out/sd.img conv=notrunc seek=2048
          ''
        ;

        maaxboardAarch64Image = pkgs.runCommand "maaxboard-aarch64-image" { nativeBuildInputs = with pkgs; [ dosfstools util-linux ]; }
          ''
            mkdir -p $out
            dd if=/dev/zero of=$out/sd.img bs=1M count=256

            sfdisk --no-reread --no-tell-kernel $out/sd.img <<EOF
              label: dos

              start=98304,size=64M,type=b
              start=229376,size=64M,type=b
              start=360448,size=64M,type=b
            EOF

            dd if=${avnetImxMkimage}/flash.bin of=$out/sd.img conv=notrunc bs=1K seek=33

            dd if=/dev/zero of=fat32_part.img bs=1M count=64
            mkfs.vfat -F 32 fat32_part.img
            dd if=fat32_part.img of=$out/sd.img bs=512 seek=98304
            dd if=fat32_part.img of=$out/sd.img bs=512 seek=229376
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

          patches = [
            ./patches/imx-atf_enable_debug_console.patch
          ];

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
            ".config"
            "u-boot.bin"
            "arch/arm/dts/maaxboard.dtb"
            "spl/u-boot-spl.bin"
            "tools/mkimage"
            "u-boot-nodtb.bin"
          ];
          # Nix buildUBoot tries to apply Rasbperry Pi specific patches to the source
          # which doesn't work for certain forks.
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
            ".config"
            "u-boot-rockchip.bin"
            "u-boot.bin"
            "u-boot.itb"
            "idbloader.img"
          ];
          src = mainlineUboot;
        };

        # TODO:
        # fixup SD card image to actually be reproducible
        # 'bootflow hunt ethernet' needs to happen for as part of the normal boot flow
        # rather than being in the environment which we overwrite
        nanopir5cAarch64Uboot = pkgs.pkgsCross.aarch64-multiplatform.buildUBoot rec {
          extraMeta.platforms = [ "aarch64-linux" ];
          version = ubootVersion;
          defconfig = "nanopi-r5c-rk3568_defconfig";
          BL31 = "${pkgs.pkgsCross.aarch64-multiplatform.armTrustedFirmwareRK3568}/bl31.elf";
          ROCKCHIP_TPL = pkgs.rkbin.TPL_RK3568;
          filesToInstall = [
            ".config"
            "u-boot-rockchip.bin"
            "u-boot.bin"
            "u-boot.itb"
            "idbloader.img"
          ];
          extraConfig = ''
            CONFIG_USE_ETHPRIME=y
            CONFIG_ETHPRIME=eth0
            CONFIG_ENV_FAT_INTERFACE=mmc
            CONFIG_ENV_IS_NOWHERE=n
            CONFIG_ENV_IS_IN_FAT=y
            CONFIG_ENV_FAT_DEVICE_AND_PART="1:auto"
            CONFIG_DWC_ETH_QOS=y
            CONFIG_DWC_ETH_QOS_ROCKCHIP=y
          '';
          src = mainlineUboot;
        };

        nanopir5cAarch64Image = pkgs.runCommand "nanopi-r5c-aarch64-image" {}
          ''
            mkdir -p $out
            dd if=/dev/zero of=$out/sd.img bs=1M count=128
            dd if=${nanopir5cAarch64Uboot}/idbloader.img of=$out/sd.img conv=notrunc seek=8
            dd if=${nanopir5cAarch64Uboot}/u-boot.itb of=$out/sd.img conv=notrunc seek=2048
          ''
        ;

        tx2Uboot = pkgs.pkgsCross.aarch64-multiplatform.buildUBoot rec {
          extraMeta.platforms = [ "aarch64-linux" ];
          version = ubootVersion;
          defconfig = "p2771-0000-500_defconfig";
          filesToInstall = [
            ".config"
            "u-boot.bin"
            "u-boot.dtb"
          ];
          extraPatches = [
            ./patches/tx2_uboot_dont_check_linux_magic.patch
          ];
          extraConfig = ''
            # The default is 8MiB which is too small for some images
            # Make it 64MiB instead.
            CONFIG_SYS_BOOTM_LEN=0x4000000
          '';
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
            ".config"
            "u-boot.bin"
          ];
          src = mainlineUboot;
        };

        rpi5Aarch64Uboot = pkgs.pkgsCross.aarch64-multiplatform.buildUBoot rec {
          extraMeta.platforms = [ "aarch64-linux" ];
          version = "v2024.07";
          # There is no Raspberry Pi 5 specific config so we use the generic
          # 64-bit one.
          defconfig = "rpi_arm64_defconfig";
          filesToInstall = [
            ".config"
            "u-boot.bin"
          ];
          dontPatch = true;
          extraConfig = ''
            CONFIG_BCM2712=y
            CONFIG_CMD_BOOTDEV=y
          '';
          src = pkgs.fetchFromGitHub {
            owner = "au-ts";
            repo = "u-boot";
            rev = "v2024.07-rpi5";
            hash = "sha256-lQWE+KDkbmvhVa5UQ8rd0kgGsynU4NlMR9n+IVBuC/A=";
          };
        };

        ubootAarch64Odroidc4 = pkgs.pkgsCross.aarch64-multiplatform.buildUBoot rec {
          extraMeta.platforms = [ "aarch64-linux" ];
          version = ubootVersion;
          defconfig = "odroid-c4_defconfig";
          # The defconfig does not setup 'saveenv' to work properly, so we do that here.
          extraConfig = ''
            CONFIG_ENV_IS_NOWHERE=n
            CONFIG_ENV_IS_IN_MMC=y
            CONFIG_ENV_OFFSET=0x10000000
          '';
          filesToInstall = [
            ".config"
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

        hifiveP550Riscv64Uboot = pkgs.pkgsCross.riscv64.buildUBoot rec {
            extraMeta.platforms = [ "riscv64-linux" ];
            version = "u-boot-2024.01-EIC7X";
            defconfig = "hifive_premier_p550_defconfig";

            filesToInstall = [
              ".config"
              "u-boot.bin"
            ];

            # Either we add these flags to ignore these warnings that show up as errors
            # or we have to use an older GCC.
            prePatch = ''
              echo "KBUILD_CFLAGS += -Wno-implicit-function-declaration -Wno-incompatible-pointer-types -Wno-int-conversion" >> Makefile
            '';

            src = pkgs.fetchFromGitHub {
              owner = "eswincomputing";
              repo = "u-boot";
              rev = "27cda8f697e3990b4bea728c1066733259b7aa95";
              hash = "sha256-0vqd3QdnBAuwA74PxDVLuVkcPGEYyMWsCFX3zpS0LLA=";
            };
        };

        milkvJupiterRiscv64Uboot = pkgs.pkgsCross.riscv64.buildUBoot rec {
            extraMeta.platforms = [ "riscv64-linux" ];
            version = "k1-bl-v2.2.7-release";
            defconfig = "k1_defconfig";

            filesToInstall = [
              ".config"
              "u-boot.bin"
            ];

            # Nix buildUBoot tries to apply Rasbperry Pi specific patches to the source
            # which doesn't work for certain forks.
            dontPatch = true;

            src = pkgs.fetchFromGitHub {
              owner = "Ivan-Velickovic";
              repo = "uboot_spacemit_k1";
              rev = "k1-bl-v2.2.7-release";
              hash = "sha256-Y5SGPCn4PzTpD/oNHMN8ExXsX1+AGAbSQlO6u9vRhUg=";
            };
        };

        star64Riscv64Uboot = pkgs.pkgsCross.riscv64.buildUBoot rec {
            extraMeta.platforms = [ "riscv64-linux" ];
            version = ubootVersion;
            defconfig = "starfive_visionfive2_defconfig";

            extraMakeFlags = [
              "OPENSBI=${opensbi-riscv64-pine64-star64}/share/opensbi/lp64/generic/firmware/fw_dynamic.bin"
            ];

            filesToInstall = [
              ".config"
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

        # output: result/share/opensbi/lp64/fpga/cheshire/firmware/fw_payload.elf*
        cheshireRiscv64OpenSBI = (pkgs.pkgsCross.riscv64.opensbi.overrideAttrs (old: {
          # Using a fork because we want FW_TEXT_START=0x80000000 but also, more importantly,
          # that newer openSBI tries to use semihosting which is *extremely slow* under a debugger,
          # and there is no way to just turn it off
          src = pkgs.fetchFromGitHub {
            owner = "pulp-platform";
            repo = "opensbi";
            # cheshire branch
            rev = "1156a7be33d5017a56815a283f640e8961fa9588";
            hash = "sha256-CNEuV3TC4br7OE9nOeBKsArzp6o8Fy2XQrVCozeVMEE=";
          };

          makeFlags = old.makeFlags ++ [
            "PLATFORM_RISCV_XLEN=64"
            "PLATFORM_RISCV_ISA=rv64imafdc_zicsr_zifencei"
            "PLATFORM_RISCV_ABI=lp64"
            "FW_DYNAMIC=y"
            "FW_JUMP=y"
            "FW_JUMP_ADDR=0x90000000"
            "FW_PAYLOAD=y"
          ];

          patches = [
            # creates a timing channel
            ./patches/cheshire_no_vga.patch
          ];
        })).override {
          withPlatform = "fpga/cheshire";
          withPayload = "${cheshireRiscv64Uboot}/u-boot.bin";
          withFDT = "${cheshire-sw}/cheshire.genesys2.dtb";
        };

        cheshire-sw = pkgs.pkgsCross.riscv64-embedded.stdenv.mkDerivation rec {
          name = "cheshire-sw";

          src = pkgs.fetchFromGitHub {
            owner = "pulp-platform";
            repo = "cheshire";
            # main as of 2025.08.07
            rev = "2d0b8f82356330fc58b32a508a39239de5fcb237";
            hash = "sha256-iMBa8tkRGZyam2UxA2IJ5+3EAL7495M8mOQfehz6t+Y=";
          };

          benderDeps = pkgs.stdenv.mkDerivation {
            name = "cheshire-sw-deps";
            inherit src nativeBuildInputs;

            buildPhase = ''
              runHook preBuild

              bender -d $(realpath .) checkout

              runHook postBuild
            '';

            installPhase = ''
              mkdir -p $out
              # todo not .bender subdir
              cp -r .bender/ $out/
            '';

            # cant't use default fixup for FODs
            fixupPhase = ''
              # references input paths
              find $out/ -name "*.sample" -type f -delete
              find $out/ -name ".git" -type d -exec rm -rf {} +
              rm -rf $out/.bender/git/db
            '';

            dontCheckForBrokenSymlinks = true;

            outputHash = "sha256-D25ZKufRKXEvZKgoqAjMgIb2F5aOZuGk5ytwsBOcr1I=";
            outputHashMode = "recursive";
            outputHashAlgo = "sha256";
          };

          nativeBuildInputs = [ pkgs.which pkgs.bender pkgs.git pkgs.cacert pkgs.findutils pkgs.flock pkgs.bash pkgs.dtc (pkgs.python3.withPackages (ps: with ps; [requests hjson mako pyyaml tabulate yapf flatdict setuptools])) ];

          printfDep = pkgs.fetchFromGitHub {
            owner = "mpaland";
            repo = "printf";
            rev = "0dd4b64bc778bf55229428cefccba4c0a81f384b";
            hash = "sha256-tgLJNJw/dJGQMwCmfkWNBvHB76xZVyyfVVplq7aSJnI=";
          };

          patchPhase = ''
            cp -r ${benderDeps}/.bender .
            chmod -R +w .bender/

            rm -rf sw/deps/printf
            cp -r ${printfDep} sw/deps/printf
            chmod -R +w sw/deps/printf

            patchShebangs .

            # LTO breaks compilation
            sed -i 's/-flto -Wl,-flto/-Wno-error/g' sw/sw.mk

            # tell make deps up to date.
            touch .bender/.chs_deps
          '';

          buildPhase = let
            prefix = pkgs.pkgsCross.riscv64-embedded.stdenv.targetPlatform.config;
          in ''
            make sw/boot/zsl.rom.bin sw/boot/cheshire.genesys2.dtb \
              CHS_SW_AR=${prefix}-ar \
              CHS_SW_OBJCOPY=${prefix}-objcopy \
              CHS_SW_OBJDUMP=${prefix}-objdump \
              CHS_SW_CC=${prefix}-gcc \
              CHS_SW_LTOPLUG= \
              CHS_SW_ARFLAGS= \
              SHELL=$(which bash) \
              CHS_SW_GCC_BINROOT=$(dirname $(which ${prefix}-gcc))
          '';

          dontFixup = true;

          installPhase = ''
            mkdir -p $out/
            cp sw/boot/zsl.rom.bin $out/zsl.rom.bin
            cp sw/boot/cheshire.genesys2.dtb $out/cheshire.genesys2.dtb
          '';
        };

        cheshireRiscv64Uboot = (pkgs.pkgsCross.riscv64.buildUBoot {
            version = "pulp-platform-2025-06-21";

            src = pkgs.fetchFromGitHub {
              owner = "pulp-platform";
              repo = "u-boot";
              # cheshire branch
              rev = "90ec8e2e250bce3792a3e57ba776be0894ebd632";
              hash = "sha256-tOZELsWd7lDwsDQPg7yOByR4obq6Bc8+MsF5NU8S1Ws=";
            };

            extraMeta.platforms = [ "riscv64-linux" ];
            defconfig = "pulp-platform_cheshire_defconfig";

            extraConfig = ''
              CONFIG_AUTOBOOT=y
              CONFIG_BOOTDELAY=0
              CONFIG_BOOTCOMMAND="setenv bootcmd_gdb 'bootm 0x90000000 - ''${fdtcontroladdr}'; echo 'First load the uImage as a binary to 0x90000000, then run bootcmd_gdb;'"
            '';

            # CONFIG_DEBUG_UART=y
            # CONFIG_DEBUG_UART_BASE=0x03002000
            # CONFIG_DEBUG_UART_CLOCK=50000000
            # CONFIG_DEBUG_UART_BOARD_INIT=y
            # CONFIG_DEBUG_UART_ANNOUNCE=y
            # CONFIG_DEBUG_UART_BOARD_INIT=n
            # CONFIG_DEBUG_UART_SHIFT=2

            filesToInstall = [
              ".config"
              "u-boot"
              "u-boot.bin"
            ];
        }).overrideAttrs {
          # remove the raspberry pi patch present in nixos-25.05, which has been removed for unstable nixpkgs
          # at the time of writing.
          patches = [];
        };

        # taken from pulp-platform/cheshire sw/sw.mk
        # for genesys2 FPGA.
        cheshireRiscv64Image = let
          vars = {
            CHS_SW_DISK_SIZE = "16M";
            CHS_SW_ZSL_TGUID = "0269B26A-FD95-4CE4-98CF-941401412C62";
            CHS_SW_DTB_TGUID = "BA442F61-2AEF-42DE-9233-E4D75D3ACB9D";
            CHS_SW_FW_TGUID = "99EC86DA-3F5B-4B0D-8F4B-C4BACFA5F859";
          };
        in pkgs.runCommand "cheshire-riscv64-image" { nativeBuildInputs = [ pkgs.gptfdisk ]; } ''
            mkdir -p $out

            # We could do something smarter where we precompute the size of fw_payload.bin
            # so that the partition is smaller and it boots faster. But it boots reasonably
            # quickly now, so it's OK.

            truncate -s ${vars.CHS_SW_DISK_SIZE} $out/sd.img
            sgdisk --clear --set-alignment=1 \
                    --new=1:64:96 --typecode=1:${vars.CHS_SW_ZSL_TGUID} \
                    --new=2:128:159 --typecode=2:${vars.CHS_SW_DTB_TGUID} \
                    --new=3:2048:8191 --typecode=3:${vars.CHS_SW_FW_TGUID} \
                    --new=4:8192:24575 --typecode=4:8300 \
                    --new=5:24576:0 --typecode=5:8200 \
                    $out/sd.img

            dd if=${cheshire-sw}/zsl.rom.bin of=$out/sd.img bs=512 seek=64 conv=notrunc
            dd if=${cheshire-sw}/cheshire.genesys2.dtb of=$out/sd.img bs=512 seek=128 conv=notrunc
            dd if=${cheshireRiscv64OpenSBI}/share/opensbi/lp64/fpga/cheshire/firmware/fw_payload.bin of=$out/sd.img bs=512 seek=2048 conv=notrunc

            # linux not supported; partitions 4 and 5 are unused.
            # dd if=uImage of=$out/sd.img bs=512 seek=8192 conv=notrunc
          ''
        ;

        allImages = pkgs.runCommand "all-images" { nativeBuildInputs = with pkgs; [ gnutar gzip ]; }
          ''
            mkdir -p $out

            cp ${star64Riscv64Image}/sd.img $out/star64-riscv64.img
            cp ${maaxboardAarch64Image}/sd.img $out/maaxboard-aarch64.img
            cp ${odroidc4Aarch64Image}/sd.img $out/odroidc4-aarch64.img
            cp ${rpi4Aarch64Image}/sd.img $out/rpi4-aarch64.img
            cp ${rpi5Aarch64Image}/sd.img $out/rpi5-aarch64.img
            cp ${rockpro64Aarch64Image}/sd.img $out/rockpro64-aarch64.img
            cp ${nanopir5cAarch64Image}/sd.img $out/nanopir5c-aarch64.img
            cp ${cheshireRiscv64Image}/sd.img $out/cheshire-riscv64.img

            cd $out
            for f in *.img; do tar cf - $f | gzip -9 > `basename $f`.tar.gz; done
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

        packages.rpi5-aarch64-uboot = rpi5Aarch64Uboot;
        packages.rpi5-aarch64-image = rpi5Aarch64Image;

        packages.rockpro64-aarch64-uboot = rockpro64Aarch64Uboot;
        packages.rockpro64-aarch64-image = rockpro64Aarch64Image;

        packages.nanopir5c-aarch64-uboot = nanopir5cAarch64Uboot;
        packages.nanopir5c-aarch64-image = nanopir5cAarch64Image;

        packages.hifive-p550-riscv64-uboot = hifiveP550Riscv64Uboot;

        packages.milkv-jupiter-riscv64-uboot = milkvJupiterRiscv64Uboot;

        packages.tx2-uboot = tx2Uboot;

        packages.cheshire-sw = cheshire-sw;
        packages.cheshire-opensbi = cheshireRiscv64OpenSBI;
        packages.cheshire-uboot = cheshireRiscv64Uboot;
        packages.cheshire-image = cheshireRiscv64Image;

        packages.default = allImages;
      });
}
