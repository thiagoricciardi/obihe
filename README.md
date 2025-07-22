# OBiHe - OpenWrt Image Builder Helper

This is OpenWrt Image Builder Helper, a simple tool to help build OpenWrt in a customized way using OpenWrt Image Builder.\
With OBiHe, it's relatively easy to create persistent custom builds for multiple devices across many OpenWrt versions.

## Installation

This script uses OpenWrt ImageBuilder, so it has the same dependencies.\
Please, be sure to follow the [Prerequisites](https://openwrt.org/docs/guide-user/additional-software/imagebuilder#prerequisites) section of the OpenWrt Image Builder documentation.

With that done, there is nothing else to install, you only need to add your customization and run the script.\
If there is something missing the script should inform you.

## Compatibility

This script should be compatible (but not extensively tested) with all OpenWrt releases from version 17.01 (LEDE) up to the latest version, including the release candidates, but not the snapshot version.

## Getting started

The simplest configuration that can be made is to create a device file and build it.\
The most complex situation that it can handle now is to add custom root files, custom packages to the system and run pre/post-build functions automatically.

### Device file configuration

The device file is a script include. It must be named `config` inside a device directory, but it can have any file name when alone.

The `PLATFORM` variable is mandatory. It's syntax is OpenWrt's TARGET/SUB_TARGET.\
Platform examples: `x86/64` or `mediatek/filogic`\
**[Tip]** It uses the same syntax as the [firmware selector](https://firmware-selector.openwrt.org/), use it to browse your device and copy it :wink:.

The `PROFILE` variable should be configured when necessary.\
Profile example: `openwrt_one`\
**[Tip]** The firmware selector sets the profile as the `id` query string in the permalink.\
e.g.: Selecting "OpenWrt One" as the device. Look at your browser's URL: ...?version=24.10.0&target=mediatek%2Ffilogic&id=**openwrt\_one**

Another important configuration is the `PACKAGES` variable.\
It should contain the OpenWrt packages to be embedded in the image.\
The packages should be separated by whitespaces.\
Packages example: `luci-ssl luci-app-opkg luci-app-wol`\
See the [packages](https://openwrt.org/packages/start) in the OpenWrt website for more information.

To get to know more about the configuration file, please check the `examples` directory of this repository.

### The root device directory

To use the root directory the device file must be named `config` inside a device directory tree and the root filesystem directory must be named `root`.\
The root directory will be exactly what the name implies, the files inside it will be placed in the root (`/`) directory of the device just before packing the image.

### The packages device directory

Like in the root directory, to use the packages directory, the device file must be named `config` and be placed directly inside the device directory.\
To add custom packages to the system, place custom `ipk` packages inside the `packages` device directory.

### The full device directory structure (example)

```
devices/mydevice
├── config » This is the device configuration file
├── packages » Packages device directory
│   ├── package1.ipk
│   └── package2.ipk
└── root » Root device directory
    └── etc
        ├── crontabs
        │   └── root
        ├── rc.local
        └── uci-defaults
```

### Examples

There are some examples in the `examples` folder of this repository, please check them for a more practical approach.

### Run it

To run the script simply run the `build.sh` using the arguments.\
The first argument points to the device file or directory and the second argument is the version you want to build.\
The third argument is optional and it is the base URL to the OpenWrt mirror of your choice, if not supplied it uses the official OpenWrt download directory.

Example:
```
./build.sh example/simple 23.05.5 https://mirrors.cicku.me/openwrt/
```

OpenWrt mirrors can be found at https://openwrt.org/downloads#mirrors

### Output

The images will be under `./bin/<path/to/device>/` directory.

## License

This tool is licensed under GPL-2.0
