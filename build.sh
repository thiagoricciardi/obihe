#!/usr/bin/env sh

# Load device file from first argument
DEVICE="$1"
#shift
# Load versions from remaining arguments
#VERSIONS="$*"
# Load version from second argument
VERSION="$2"

# Load current script directory path
_my_dir="$( cd "$( [ -z "$BASH_SOURCE" ] && dirname "$0" || dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Output directory
OUT_DIR="$_my_dir/bin"
# Temporary directory
TMP_DIR="/tmp/openwrt"
# Temporary output
TMP_OUT="$TMP_DIR/out"

# RAM disk size used in compilation (empty to do not create)
# This will use the temporary directory as RAM disk
RAMDISK_SIZE="10G"

# Get major version
_majorver=$(echo $VERSION | cut -d'.' -f1)

# Fix device file (you can use only device file name if the file is in devices directory)
_devfile="$DEVICE"
[ -r "$_devfile" ] || _devfile="devices/$DEVICE"

# --- Main functions ---

show_usage() {
	echo "Usage: $0 <device_file> <version>"
}
err_exit() {
	_err="$1"
	[ -z "_err" ] && _err=1
	exit $_err
}
isFunction() { declare -F -- "$@" >/dev/null; }

# --- Initial checks ---

# If device or version is empty
if [ -z "$DEVICE" -o -z "$VERSION" ] ; then
	echo "Too few arguments."
	show_usage
	err_exit
fi
# If there are more than 2 arguments
if [ -n "$3" ] ; then
	echo "Too many arguments."
	show_usage
	err_exit
fi
# If device file is not readable
if [ ! -r "$_devfile" ] ; then
	echo "Access denied to $_devfile."
	err_exit
fi

# Import device file
. "$_devfile"

# Check if required variables have been filled
if [ -z "$PLATFORM" ] ; then
	echo "Variable \$PLATFORM is required, please check the device file $_devfile"
	err_exit
fi

# Fill target and subtarget from platform
TARGET=$(echo "$PLATFORM" | cut -d'/' -f1)
SUBTARGET=$(echo "$PLATFORM" | cut -d'/' -f2)

# If target and subtarget are empty
if [ -z "$TARGET" -o -z "$SUBTARGET" ] ; then
	echo "Invalid \$PLATFORM, the format should be TARGET/SUBTARGET, was $PLATFORM"
	err_exit
fi

# --- Validations ---

# if check for commands
_CMDs="qemu-img jq gzip sha256sum make wget"
_INSTALL=""
for _cmd in $_CMDs ; do
	command -v $_cmd > /dev/null
	_err="$?"
	if [ "$_err" -ne "0" ] ; then
		_INSTALL="$_INSTALL $_cmd"
	fi
done
if [ -n "$_INSTALL" ] ; then
	echo "Dependencies not installed, please install$_INSTALL."
	exit 1
fi

# if SSH_IMPORT_ID check for command
if [ -n "$SSH_IMPORT_ID" ] ; then
	command -v ssh-import-id > /dev/null
	_err="$?"
	if [ "$_err" -ne "0" ] ; then
		echo "Cannot import SSH keys, please install ssh-import-id."
		exit $_err
	fi
fi

# Check for FILES consistency
if [ -n "$FILES" -a ! -d "$FILES" ] ; then
	echo "$FILES is not a directory, root files must be in a directory."
	exit 1
fi

# Check if PARTSIZE variables are > 0
if [ -n "$KERNEL_PARTSIZE" ] ; then
	if [ ! "$KERNEL_PARTSIZE" -gt "0" ] ; then
		echo "KERNEL_PARTSIZE should be numeric greater than 0 (in MB)."
		exit 1
	fi
fi
if [ -n "$ROOTFS_PARTSIZE" ] ; then
	if [ ! "$ROOTFS_PARTSIZE" -gt "0" ] ; then
		echo "ROOTFS_PARTSIZE should be numeric greater than 0 (in MB)."
		exit 1
	fi
fi

# Check if custom functions exists and set the run variables
_prebuild=""
if [ -n "$BUILD_BEFORE" ] ; then
	if isFunction "$BUILD_BEFORE" ; then
		_prebuild="$BUILD_BEFORE"
	fi
fi
_posbuild=""
if [ -n "$BUILD_AFTER" ] ; then
	if isFunction "$BUILD_AFTER" ; then
		_posbuild="$BUILD_AFTER"
	fi
fi

# --- Script ---

# make output dir
mkdir -p "$OUT_DIR"

# make build dir
mkdir -p "$TMP_DIR"
# create RAM disk if requested
if [ -n "$RAMDISK_SIZE" ]; then
	echo "Creating RAM Disk, this requires elevated privileges, please type your password if requested..."
	sudo mount -t tmpfs -o rw,size="$RAMDISK_SIZE" tmpfs "$TMP_DIR"
fi
mkdir -p "$TMP_OUT"

# copy root override files if exists and FILES is empty
if [ -d "${_my_dir}/root" -a -z "$FILES" ] ; then
	cp --preserve=all -rLv "${_my_dir}/root" "$TMP_DIR/"
# else move the files if FILES is a directory
elif [ -d "$FILES" ] ; then
	mkdir -p "$TMP_DIR/root"
	cp --preserve=all -rLv "$FILES/*" "$TMP_DIR/root/"
else
	echo "No aditional root files are being added."
fi

# Add SSH keys to ROOT if needed
if [ -n "$SSH_IMPORT_ID" ] ; then
	echo "Importing SSH IDs..."
	mkdir -p "$TMP_DIR/root"
	for _id in $SSH_IMPORT_ID ; do
		ssh-import-id -o "$TMP_DIR/root/etc/dropbear/authorized_keys" $_id
	done
fi

# Set FILES if root exists
[ -d "$TMP_DIR/root" ] && FILES="$TMP_DIR/root"

# Configure build variables
[ -n "$FILES" ] && _FILES="FILES=\"$FILES\""
[ -n "$PROFILE" ] && _PROFILE="PROFILE=\"$PROFILE\""
[ -n "$PACKAGES" ] && _PACKAGES="PACKAGES=\"$PACKAGES\""
[ -n "$KERNEL_PARTSIZE" ] && _KERNEL_PARTSIZE="CONFIG_TARGET_KERNEL_PARTSIZE=\"$KERNEL_PARTSIZE\""
[ -n "$ROOTFS_PARTSIZE" ] && _ROOTFS_PARTSIZE="CONFIG_TARGET_ROOTFS_PARTSIZE=\"$ROOTFS_PARTSIZE\""

# Save current directory
_PWD=$PWD

# --- Building ---

_VER=$VERSION-$TARGET-$SUB_TARGET
echo ; echo
echo "Making image for $_VER"
echo ; echo
_IMGBLD=openwrt-imagebuilder-$_VER.Linux-x86_64
# download openwrt builder
echo "Downloading $_IMGBLD"
wget -qO- --show-progress https://downloads.openwrt.org/releases/$VERSION/targets/$TARGET/$SUB_TARGET/$_IMGBLD.tar.xz | tar -xJ --directory $TMP_DIR/
echo "Configuring..."
# enter the image directory
cd $TMP_DIR/$_IMGBLD/
# Backup and edit config file
_CFG_BKP=config.bkp
_CFG_OUT=config.out
_CFG_CFG=.config
[ ! -e "$_CFG_BKP" ] && (cp $_CFG_CFG $_CFG_BKP)
cp $_CFG_BKP $_CFG_CFG
# Remove sizes from config (if they are specified)
[ -n "$_KERNEL_PARTSIZE" ] && (grep --invert-match CONFIG_TARGET_KERNEL_PARTSIZE $_CFG_CFG > $_CFG_OUT ; mv $_CFG_OUT $_CFG_CFG)
[ -n "$_ROOTFS_PARTSIZE" ] && (grep --invert-match CONFIG_TARGET_ROOTFS_PARTSIZE $_CFG_CFG > $_CFG_OUT ; mv $_CFG_OUT $_CFG_CFG)
rm $_CFG_OUT

# run pre-build function if exists
[ -z "$_prebuild" ] || $_prebuild
echo "Making..."
# make the image
make clean
sh -ac "make image $_PROFILE $_FILES $_PACKAGES $_KERNEL_PARTSIZE $_ROOTFS_PARTSIZE"
# run post-build function if exists
[ -z "$_posbuild" ] || $_posbuild

# copy output
if [ -z "$(ls -A \"$TMP_OUT\")" ] ; then
	cp -av bin/targets/$TARGET/$SUB_TARGET/* $OUT_DIR/
else
	cp -av $TMP_OUT/* $OUT_DIR/
fi

# do sha256sums in outdir
echo "Calculating checksums..."
cd $OUT_DIR
rm sha256sum 2> /dev/null
sha256sum * > sha256sum
cd $_PWD

# clear build dir
rm -r $TMP_DIR/$_IMGBLD
rm -r $TMP_OUT/*

# remove other build directories
rmdir $TMP_OUT
[ -d "$TMP_DIR/root" ] && rm -r $TMP_DIR/root

# remove RAM disk
if [ -n "$RAMDISK_SIZE" ]; then
	echo "Removing RAM Disk..."
	sudo umount $TMP_DIR
fi

# remove build dir
rmdir $TMP_DIR
