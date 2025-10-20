{
  fetchFromGitHub,
  stdenv,
  lib,
  runCommand,
  util-linux,
  buildUBoot,
  ubootSrc,
  armTrustedFirmwareRK3399,
}:
let
in
rec {
  uboot = buildUBoot rec {
    extraMeta.platforms = [ "aarch64-linux" ];
    defconfig = "rockpro64-rk3399_defconfig";
    BL31 = "${armTrustedFirmwareRK3399}/bl31.elf";
    filesToInstall = [
      ".config"
      "u-boot-rockchip.bin"
      "u-boot.bin"
      "u-boot.itb"
      "idbloader.img"
    ];
    version = ubootSrc.rev;
    src = ubootSrc;
  };

  image = runCommand "rockpro64-aarch64-image" {}
    ''
      mkdir -p $out
      dd if=/dev/zero of=$out/sd.img bs=1M count=64
      dd if=${uboot}/u-boot-rockchip.bin of=$out/sd.img conv=notrunc seek=64
    ''
  ;
}
