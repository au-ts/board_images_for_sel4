{
  fetchFromGitHub,
  stdenv,
  lib,
  writeTextFile,
  runCommand,
  mtools,
  dosfstools,
  util-linux,
  buildUBoot,
  ubootSrc,
}:
let
  config = writeTextFile {
    name = "config.txt";
    destination = "/config.txt";
    text = ''
      enable_uart=1
      arm_64bit=1
      kernel=u-boot.bin
    '';
  };
in
rec {
  firmware = fetchFromGitHub {
    owner = "raspberrypi";
    repo = "firmware";
    rev = "1.20250430";
    hash = "sha256-U41EgEDny1R+JFktSC/3CE+2Qi7GJludj929ft49Nm0=";
  };

  uboot = buildUBoot rec {
    extraMeta.platforms = [ "aarch64-linux" ];
    defconfig = "rpi_4_defconfig";
    filesToInstall = [
      ".config"
      "u-boot.bin"
    ];
    version = ubootSrc.rev;
    src = ubootSrc;
  };

  image = runCommand "image-aarch64-rpi4" { nativeBuildInputs = [ mtools dosfstools util-linux ]; }
    ''
      mkdir -p $out/firmware

      dd if=/dev/zero of=$out/boot_part.img bs=1M count=64
      mkfs.vfat $out/boot_part.img

      cp ${uboot}/u-boot.bin $out
      cp ${firmware}/boot/start4.elf $out/firmware
      cp ${firmware}/boot/fixup4.dat $out/firmware
      cp ${firmware}/boot/bcm2711-rpi-4-b.dtb $out/firmware
      cp -r ${firmware}/boot/overlays $out/firmware/overlays

      mcopy -i $out/boot_part.img -s $out/firmware/* ${uboot}/u-boot.bin ${config}/config.txt ::

      dd if=/dev/zero of=$out/sd.img bs=1M count=128
      sfdisk --no-reread --no-tell-kernel $out/sd.img <<EOF
        label: dos

        start=2048,size=64M,type=b
      EOF
      dd if=$out/boot_part.img of=$out/sd.img conv=notrunc seek=2048
    ''
  ;
}
