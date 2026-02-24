{
  fetchFromGitHub,
  stdenv,
  lib,
  runCommand,
  util-linux,
  buildUBoot,
  buildOpensbi,
  gptfdisk,
  ubootVisionFive2,
}:
let
in
rec {
  opensbi = buildOpensbi.overrideAttrs (oldattrs: {
    makeFlags = [
      "FW_TEXT_START=0x40000000"
    ] ++ oldattrs.makeFlags;
  });

  image = runCommand "star64-riscv64-image" { nativeBuildInputs = [ gptfdisk ]; }
    ''
      mkdir -p $out
      dd if=/dev/zero of=$out/sd.img bs=1M count=64
      sgdisk --clear \
        --set-alignment=2 \
        --new=1:4096:8191 --change-name=1:spl --typecode=1:2E54B353-1271-4842-806F-E436D6AF6985\
        --new=2:8192:16383 --change-name=2:uboot --typecode=2:BC13C2FF-59E6-4262-A352-B275FD6F7172  \
        $out/sd.img
      dd if=${ubootVisionFive2}/u-boot-spl.bin.normal.out of=$out/sd.img conv=notrunc seek=4096
      dd if=${ubootVisionFive2}/u-boot.itb of=$out/sd.img conv=notrunc seek=8192
    ''
  ;
}
