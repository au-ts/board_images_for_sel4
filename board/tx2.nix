{
  fetchFromGitHub,
  stdenv,
  lib,
  runCommand,
  util-linux,
  buildUBoot,
  ubootSrc,
}:
let
in
rec {
  uboot = buildUBoot rec {
    extraMeta.platforms = [ "aarch64-linux" ];
    defconfig = "p2771-0000-500_defconfig";
    filesToInstall = [
      ".config"
      "u-boot.bin"
      "u-boot.dtb"
    ];
    extraPatches = [
      ../patches/tx2_uboot_dont_check_linux_magic.patch
    ];
    extraConfig = ''
      # The default is 8MiB which is too small for some images
      # Make it 64MiB instead.
      CONFIG_SYS_BOOTM_LEN=0x4000000
    '';
    src = ubootSrc;
    version = ubootSrc.rev;
  };
}
