{
  fetchFromGitHub,
  stdenv,
  lib,
  runCommand,
  util-linux,
  buildUBoot,
  ubootSrc,
  rkbin,
  armTrustedFirmwareRK3568,
}:
let
in
rec {
  uboot = buildUBoot rec {
    extraMeta.platforms = [ "aarch64-linux" ];
    defconfig = "rock-3b-rk3568_defconfig";
    BL31 = "${armTrustedFirmwareRK3568}/bl31.elf";
    ROCKCHIP_TPL = rkbin.TPL_RK3568;
    filesToInstall = [
      ".config"
      "u-boot-rockchip.bin"
      "u-boot.bin"
      "u-boot.itb"
      "idbloader.img"
    ];
    src = ubootSrc;
    version = ubootSrc.rev;
  };

  image = runCommand "rock3b-aarch64-image" {}
    ''
      mkdir -p $out
      dd if=/dev/zero of=$out/sd.img bs=1M count=64
      dd if=${uboot}/u-boot-rockchip.bin of=$out/sd.img conv=notrunc seek=64
    ''
  ;
}
