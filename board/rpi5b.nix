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
}:
let
in
rec {
  firmware = fetchFromGitHub {
    owner = "raspberrypi";
    repo = "firmware";
    rev = "1.20250430";
    hash = "sha256-U41EgEDny1R+JFktSC/3CE+2Qi7GJludj929ft49Nm0=";
  };

  config = writeTextFile {
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

  uboot = buildUBoot rec {
    extraMeta.platforms = [ "aarch64-linux" ];
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
    version = "v2024.07";
    src = fetchFromGitHub {
      owner = "au-ts";
      repo = "u-boot";
      rev = "v2024.07-rpi5";
      hash = "sha256-lQWE+KDkbmvhVa5UQ8rd0kgGsynU4NlMR9n+IVBuC/A=";
    };
  };

  image = runCommand "image-aarch64-rpi5" { nativeBuildInputs = [ mtools dosfstools util-linux ]; }
    ''
      mkdir -p $out/firmware

      dd if=/dev/zero of=$out/boot_part.img bs=1M count=64
      mkfs.vfat $out/boot_part.img

      cp ${uboot}/u-boot.bin $out
      cp ${firmware}/boot/start4.elf $out/firmware
      cp ${firmware}/boot/fixup4.dat $out/firmware
      cp ${firmware}/boot/bcm2712-rpi-5-b.dtb $out/firmware
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
