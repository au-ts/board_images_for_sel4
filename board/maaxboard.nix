{
  fetchFromGitHub,
  fetchurl,
  stdenv,
  lib,
  runCommand,
  util-linux,
  dosfstools,
  buildUBoot,
  musl,
  zlib,
  dtc,
  aarch64-multiplatform,
}:
let
in
rec {
  uboot = buildUBoot rec {
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
    src = fetchFromGitHub {
      owner = "Avnet";
      repo = "uboot-imx";
      rev = version;
      hash = "sha256-IuMaAmS2jyckLq4+vTwZaf1H0foh7DwicV5vrDKDC9M=";
    };
  };

  avnetImxMkimage = stdenv.mkDerivation rec {
    name = "avnet-imx-mkimage";
    src = fetchFromGitHub {
      owner = "Avnet";
      repo = "imx-mkimage";
      rev = "develop_imx_4.14.78_1.0.0_ga";
      hash = "sha256-GTfbwkFXGbNoy/QbGyZS2VkL9OMBIvRxck3bFbopu50=";
    };

    nativeBuildInputs = [ musl zlib.dev zlib.static dtc ];

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
      cp ${uboot}/u-boot-nodtb.bin iMX8M
      cp ${uboot}/u-boot-spl.bin iMX8M
      cp ${uboot}/maaxboard.dtb iMX8M/fsl-imx8mq-ddr4-arm2.dtb
      cp ${uboot}/mkimage iMX8M/mkimage_uboot

      cp ${atf}/bl31.bin iMX8M/

      cp ${firmware}/ddr4_dmem_1d_202006.bin iMX8M/ddr4_dmem_1d.bin
      cp ${firmware}/ddr4_dmem_2d_202006.bin iMX8M/ddr4_dmem_2d.bin
      cp ${firmware}/ddr4_imem_1d_202006.bin iMX8M/ddr4_imem_1d.bin
      cp ${firmware}/ddr4_imem_2d_202006.bin iMX8M/ddr4_imem_2d.bin
      cp ${firmware}/signed_hdmi_imx8m.bin iMX8M/
    '';

    installPhase = ''
      mkdir -p $out
      cp iMX8M/flash.bin $out/
    '';
  };

  atf = stdenv.mkDerivation rec {
    name = "avnet-imx-atf";
    src = fetchFromGitHub {
      owner = "Avnet";
      repo = "imx-atf";
      rev = "maaxboard-imx_5.4.24_2.1.0";
      hash = "sha256-pDueidAeGysIj0R12NdqKBuZN/f7sCqjH1Kz8BWoYa4=";
    };

    nativeBuildInputs = [ aarch64-multiplatform.stdenv.cc ];

    makeFlags = [
      "CROSS_COMPILE=${aarch64-multiplatform.stdenv.cc.targetPrefix}"
      "PLAT=imx8mq"
    ];

    hardeningDisable = ["all"];

    prePatch = ''
      echo "TF_LDFLAGS += --no-warn-rwx-segments" >> Makefile
      echo "TF_CFLAGS_aarch64 += --param=min-pagesize=0" >> Makefile
    '';

    patches = [
      ../patches/imx-atf_enable_debug_console.patch
    ];

    installPhase = ''
      mkdir -p $out
      cp build/imx8mq/release/bl31.bin $out
    '';
  };

  firmware = aarch64-multiplatform.stdenv.mkDerivation rec {
    name = "avnet-imx-firmware";
    src = fetchurl {
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

  image = runCommand "maaxboard-aarch64-image" { nativeBuildInputs = [ dosfstools util-linux ]; }
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

}
