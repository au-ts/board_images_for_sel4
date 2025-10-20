{
  fetchFromGitHub,
  stdenv,
  lib,
  runCommand,
  util-linux,
  buildUBoot,
}:
let
in
rec {
  uboot = buildUBoot rec {
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

      src = fetchFromGitHub {
        owner = "eswincomputing";
        repo = "u-boot";
        rev = "27cda8f697e3990b4bea728c1066733259b7aa95";
        hash = "sha256-0vqd3QdnBAuwA74PxDVLuVkcPGEYyMWsCFX3zpS0LLA=";
      };
  };
}
