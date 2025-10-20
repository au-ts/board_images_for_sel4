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
    src = ubootSrc;
    version = ubootSrc.rev;
  };

  fip = stdenv.mkDerivation rec {
    name = "odroidc4-fip";
    src = fetchFromGitHub {
      owner = "LibreELEC";
      repo = "amlogic-boot-fip";
      # No particular reason for this commit other than it is a known working version.
      rev = "0312a79cc65bf7bb3d66d33ad0660b66146bd36d";
      hash = "sha256-6EIXP1g9LPYNz5jYYrY7PKeVbwSI3DeJBo5ZK17ePMg=";
    };

    buildPhase = ''
      mkdir -p $out
      patchShebangs odroid-c4/blx_fix.sh
      bash ./build-fip.sh odroid-c4 ${uboot.outPath}/u-boot.bin $out
    ''
    ;
  };

  image = runCommand "odroidc4-aarch64-image" {}
    ''
      mkdir -p $out
      dd if=/dev/zero of=$out/sd.img bs=1M count=64
      dd if=${fip}/u-boot.bin.sd.bin of=$out/sd.img conv=notrunc bs=512 skip=1 seek=1
      dd if=${fip}/u-boot.bin.sd.bin of=$out/sd.img conv=notrunc bs=1 count=440
    ''
  ;
}
