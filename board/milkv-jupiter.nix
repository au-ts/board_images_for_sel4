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
      version = "k1-bl-v2.2.7-release";
      defconfig = "k1_defconfig";

      filesToInstall = [
        ".config"
        "u-boot.bin"
      ];

      src = fetchFromGitHub {
        owner = "Ivan-Velickovic";
        repo = "uboot_spacemit_k1";
        rev = "k1-bl-v2.2.7-release";
        hash = "sha256-Y5SGPCn4PzTpD/oNHMN8ExXsX1+AGAbSQlO6u9vRhUg=";
      };
  };
}
