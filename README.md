# Flashable images for seL4 development

This repository aims to provide ready-to-go, reproducible, images
that can be used for seL4 development.

All images are available for download from the [releases page]
(https://github.com/au-ts/board_images_for_sel4/releases/latest).

## Available images

* Avnet MaaXBoard
* HardKernel Odroid-C4
* Raspberry Pi 4B
* Pine64 RockPRO64

## Building from source

To build from source you must be using Linux and have [Nix](https://nixos.org/download/)
installed.

To build all available images from source, run:
```sh
nix build .
```

The images will be in `result/`.

For each board there are two artifacts:
* Compiled U-Boot
* Flashable image (e.g for microSD card or eMMC)

To build a specific package run:
```sh
nix build .#<BOARD>-<ARCHITECTURE>-<ARTIFACT>
```

For example, to build the image for the Raspberry Pi 4B:
```sh
nix build .#rpi4-aarch64-image
```

The image will be in `result/`.

