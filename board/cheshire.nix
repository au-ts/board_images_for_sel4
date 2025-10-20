{
  fetchFromGitHub,
  stdenv,
  lib,
  runCommand,
  util-linux,
  buildUBoot,
  buildOpensbi,
  riscv64-embedded,
  which,
  bender,
  git,
  cacert,
  findutils,
  flock,
  bash,
  dtc,
  python3,
  gptfdisk,
}:
let
in
rec {
  # output: result/share/opensbi/lp64/fpga/cheshire/firmware/fw_payload.elf*
  opensbi = (buildOpensbi.overrideAttrs (old: {
    # Using a fork because we want FW_TEXT_START=0x80000000 but also, more importantly,
    # that newer openSBI tries to use semihosting which is *extremely slow* under a debugger,
    # and there is no way to just turn it off
    src = fetchFromGitHub {
      owner = "pulp-platform";
      repo = "opensbi";
      # cheshire branch
      rev = "1156a7be33d5017a56815a283f640e8961fa9588";
      hash = "sha256-CNEuV3TC4br7OE9nOeBKsArzp6o8Fy2XQrVCozeVMEE=";
    };

    makeFlags = old.makeFlags ++ [
      "PLATFORM_RISCV_XLEN=64"
      "PLATFORM_RISCV_ISA=rv64imafdc_zicsr_zifencei"
      "PLATFORM_RISCV_ABI=lp64"
      "FW_DYNAMIC=y"
      "FW_JUMP=y"
      "FW_JUMP_ADDR=0x90000000"
      "FW_PAYLOAD=y"
    ];

    patches = [
      # creates a timing channel
      ../patches/cheshire_no_vga.patch
    ];
  })).override {
    withPlatform = "fpga/cheshire";
    withPayload = "${uboot}/u-boot.bin";
    withFDT = "${sw}/cheshire.genesys2.dtb";
  };

  sw = riscv64-embedded.stdenv.mkDerivation rec {
    name = "cheshire-sw";

    src = fetchFromGitHub {
      owner = "pulp-platform";
      repo = "cheshire";
      # main as of 2025.08.07
      rev = "2d0b8f82356330fc58b32a508a39239de5fcb237";
      hash = "sha256-iMBa8tkRGZyam2UxA2IJ5+3EAL7495M8mOQfehz6t+Y=";
    };

    benderDeps = stdenv.mkDerivation {
      name = "cheshire-sw-deps";
      inherit src nativeBuildInputs;

      buildPhase = ''
        runHook preBuild

        bender -d $(realpath .) checkout

        runHook postBuild
      '';

      installPhase = ''
        mkdir -p $out
        # todo not .bender subdir
        cp -r .bender/ $out/
      '';

      # cant't use default fixup for FODs
      fixupPhase = ''
        # references input paths
        find $out/ -name "*.sample" -type f -delete
        find $out/ -name ".git" -type d -exec rm -rf {} +
        rm -rf $out/.bender/git/db
      '';

      dontCheckForBrokenSymlinks = true;

      outputHash = "sha256-D25ZKufRKXEvZKgoqAjMgIb2F5aOZuGk5ytwsBOcr1I=";
      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
    };

    nativeBuildInputs = [
      which
      bender
      git
      cacert
      findutils
      flock
      bash
      dtc
      (python3.withPackages (ps: with ps; [requests hjson mako pyyaml tabulate yapf flatdict setuptools])
      )
    ];

    printfDep = fetchFromGitHub {
      owner = "mpaland";
      repo = "printf";
      rev = "0dd4b64bc778bf55229428cefccba4c0a81f384b";
      hash = "sha256-tgLJNJw/dJGQMwCmfkWNBvHB76xZVyyfVVplq7aSJnI=";
    };

    patchPhase = ''
      cp -r ${benderDeps}/.bender .
      chmod -R +w .bender/

      rm -rf sw/deps/printf
      cp -r ${printfDep} sw/deps/printf
      chmod -R +w sw/deps/printf

      patchShebangs .

      # LTO breaks compilation
      sed -i 's/-flto -Wl,-flto/-Wno-error/g' sw/sw.mk

      # tell make deps up to date.
      touch .bender/.chs_deps
    '';

    buildPhase = let
      prefix = riscv64-embedded.stdenv.targetPlatform.config;
    in ''
      make sw/boot/zsl.rom.bin sw/boot/cheshire.genesys2.dtb \
        CHS_SW_AR=${prefix}-ar \
        CHS_SW_OBJCOPY=${prefix}-objcopy \
        CHS_SW_OBJDUMP=${prefix}-objdump \
        CHS_SW_CC=${prefix}-gcc \
        CHS_SW_LTOPLUG= \
        CHS_SW_ARFLAGS= \
        SHELL=$(which bash) \
        CHS_SW_GCC_BINROOT=$(dirname $(which ${prefix}-gcc))
    '';

    dontFixup = true;

    installPhase = ''
      mkdir -p $out/
      cp sw/boot/zsl.rom.bin $out/zsl.rom.bin
      cp sw/boot/cheshire.genesys2.dtb $out/cheshire.genesys2.dtb
    '';
  };

  uboot = (buildUBoot {
      version = "pulp-platform-2025-06-21";

      src = fetchFromGitHub {
        owner = "pulp-platform";
        repo = "u-boot";
        # cheshire branch
        rev = "90ec8e2e250bce3792a3e57ba776be0894ebd632";
        hash = "sha256-tOZELsWd7lDwsDQPg7yOByR4obq6Bc8+MsF5NU8S1Ws=";
      };

      extraMeta.platforms = [ "riscv64-linux" ];
      defconfig = "pulp-platform_cheshire_defconfig";

      extraConfig = ''
        CONFIG_AUTOBOOT=y
        CONFIG_BOOTDELAY=0
        CONFIG_BOOTCOMMAND="setenv bootcmd_gdb 'bootm 0x90000000 - ''${fdtcontroladdr}'; echo 'First load the uImage as a binary to 0x90000000, then run bootcmd_gdb;'"
      '';

      # CONFIG_DEBUG_UART=y
      # CONFIG_DEBUG_UART_BASE=0x03002000
      # CONFIG_DEBUG_UART_CLOCK=50000000
      # CONFIG_DEBUG_UART_BOARD_INIT=y
      # CONFIG_DEBUG_UART_ANNOUNCE=y
      # CONFIG_DEBUG_UART_BOARD_INIT=n
      # CONFIG_DEBUG_UART_SHIFT=2

      filesToInstall = [
        ".config"
        "u-boot"
        "u-boot.bin"
      ];
  }).overrideAttrs {
    # remove the raspberry pi patch present in nixos-25.05, which has been removed for unstable nixpkgs
    # at the time of writing.
    patches = [];
  };

  # taken from pulp-platform/cheshire sw/sw.mk
  # for genesys2 FPGA.
  image = let
    vars = {
      CHS_SW_DISK_SIZE = "16M";
      CHS_SW_ZSL_TGUID = "0269B26A-FD95-4CE4-98CF-941401412C62";
      CHS_SW_DTB_TGUID = "BA442F61-2AEF-42DE-9233-E4D75D3ACB9D";
      CHS_SW_FW_TGUID = "99EC86DA-3F5B-4B0D-8F4B-C4BACFA5F859";
    };
  in runCommand "cheshire-riscv64-image" { nativeBuildInputs = [ gptfdisk ]; } ''
      mkdir -p $out

      # We could do something smarter where we precompute the size of fw_payload.bin
      # so that the partition is smaller and it boots faster. But it boots reasonably
      # quickly now, so it's OK.

      truncate -s ${vars.CHS_SW_DISK_SIZE} $out/sd.img
      sgdisk --clear --set-alignment=1 \
              --new=1:64:96 --typecode=1:${vars.CHS_SW_ZSL_TGUID} \
              --new=2:128:159 --typecode=2:${vars.CHS_SW_DTB_TGUID} \
              --new=3:2048:8191 --typecode=3:${vars.CHS_SW_FW_TGUID} \
              --new=4:8192:24575 --typecode=4:8300 \
              --new=5:24576:0 --typecode=5:8200 \
              $out/sd.img

      dd if=${sw}/zsl.rom.bin of=$out/sd.img bs=512 seek=64 conv=notrunc
      dd if=${sw}/cheshire.genesys2.dtb of=$out/sd.img bs=512 seek=128 conv=notrunc
      dd if=${opensbi}/share/opensbi/lp64/fpga/cheshire/firmware/fw_payload.bin of=$out/sd.img bs=512 seek=2048 conv=notrunc

      # linux not supported; partitions 4 and 5 are unused.
      # dd if=uImage of=$out/sd.img bs=512 seek=8192 conv=notrunc
    ''
      ;
}
