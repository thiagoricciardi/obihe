#!/usr/bin/env sh
#SPDX-License-Identifier: GPL-2.0-or-later

# OBiHe - OpenWrt Image Builder Helper

# Load device file from first argument
DEVICE="$1"
#shift
# Load versions from remaining arguments
#VERSIONS="$*"
# Load version from second argument
VERSION="$2"
# Load mirror from third argument
MIRROR="$3"

# Load current script directory path
_my_dir="$( cd "$( [ -z "$BASH_SOURCE" ] && dirname "$0" || dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Output directory
[ -z "${OUT_DIR}" ] && OUT_DIR="${_my_dir}/bin/${DEVICE}"
# Temporary directory
[ -z "${TMP_DIR}" ] && TMP_DIR="$(mktemp --directory)"
# Temporary output
[ -z "${TMP_OUT}" ] && TMP_OUT="${TMP_DIR}/out"

# Get major version
MAJOR_VERSION=$(echo $VERSION | cut -d'.' -f1)

# Fix device file (you can use only device file name if the file is in devices directory)
_devfile="$DEVICE"
_devdir="$_my_dir"
[ -r "$_devfile" -o -d "$_devfile" ] || _devfile="devices/$DEVICE"
if [ -d "$_devfile" ] ; then
	_devdir="$_devfile"
	_devfile="$_devfile/config"
fi

# --- Main functions ---

show_usage() {
	echo "Usage: $0 <device_file_or_directory> <version> [mirror]"
}
err_exit() {
	_err="$1"
	[ -z "${_err}" ] && _err=1
	[ "${_err}" -ne "0" ] && ( echo ; echo "Build failed!" )
	exit $_err
}
isFunction() { type "$@" > /dev/null ; }
directoryEmpty() { [ -z "$(ls -A "$@")" > /dev/null ] ; }
toBytes() { echo $(($(echo "$1" | sed 's/E/ << 10 P/i;s/P/ << 10 T/i;s/T/ << 10 G/i;s/G/ << 10 M/i;s/M/ << 10 K/i;s/K/ << 10/i'))) ; }

# --- Initial checks ---

# RAM disk size used in compilation (define empty to do not create)
# defaults to 10G if more than 10G are available
# This will use the temporary directory as RAM disk
_mem_free="$(awk '/MemAvailable/ { gsub(/[Bb]/,"",$3)  ; print $2$3 }' /proc/meminfo)"
[ -z "${_mem_free}" ] && _mem_free="$(awk '/MemFree/ { gsub(/[Bb]/,"",$3)  ; print $2$3 }' /proc/meminfo)"
[ -z "${RAMDISK_SIZE+x}" ] && RAMDISK_SIZE="10G"
# Disable RAM disk if there is not enough memory
if [ "$(toBytes ${_mem_free})" -lt "$(toBytes ${RAMDISK_SIZE})" ] ; then
	echo_warning "Not enough free memory for a ${RAMDISK_SIZE} RAM disk, disabling it."
	RAMDISK_SIZE=""
fi

# If device or version is empty
if [ -z "$DEVICE" -o -z "$VERSION" ] ; then
	echo "Too few arguments."
	show_usage
	err_exit
fi
# If there are more than 3 arguments
if [ -n "$4" ] ; then
	echo "Too many arguments."
	show_usage
	err_exit
fi
# If device file is not readable
if [ ! -r "$_devfile" ] ; then
	echo "Access denied to \"$_devfile\"."
	err_exit
fi

# Import device file
. "$_devfile"

# Check if version matches file (only if VERSIONS variable exists)
if [ -n "$VERSIONS" ] ; then
	_ok=""
	for v in $VERSIONS ; do
		if [ "$MAJOR_VERSION" -eq "$v" ] ; then
			_ok="ok"
			break
		fi
	done
	if [ -z "$_ok" ] ; then
		echo "Device file \"$_devfile\" is only good for versions $VERSIONS"
		err_exit
	fi
fi

# Check if required variables have been filled
if [ -z "$PLATFORM" ] ; then
	echo "Variable \$PLATFORM is required, please check the device file \"$_devfile\""
	err_exit
fi

# Fill target and sub-target from platform
TARGET=$(echo "$PLATFORM" | cut -d'/' -f1)
SUB_TARGET=$(echo "$PLATFORM" | cut -d'/' -f2)

# If target and sub-target are empty
if [ -z "$TARGET" -o -z "$SUB_TARGET" ] ; then
	echo "Invalid \$PLATFORM, the format should be TARGET/SUB_TARGET, was \"$PLATFORM\""
	err_exit
fi

# --- Validations ---

# if check for commands
_CMDs="make sha256sum tar wget $REQUIRE"
[ "$MAJOR_VERSION" -ge "24" ] && _CMDs="$_CMDs zstd"
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
	err_exit
fi

# if SSH_IMPORT_ID check for command
if [ -n "$SSH_IMPORT_ID" ] ; then
	command -v ssh-import-id > /dev/null
	_err="$?"
	if [ "$_err" -ne "0" ] ; then
		echo "Cannot import SSH keys, please install ssh-import-id."
		err_exit $_err
	fi
fi

# Check for FILES consistency
if [ -n "$FILES" ] ; then
	# Adjust "files" directories to be absolute to _devdir, only if it is a relative path
	[ "$(printf '%c' "$FILES")" != '/' ] && FILES="$_devdir/$FILES"
	if [ ! -d "$FILES" ] ; then
		echo "$FILES is not a directory, root files must be in a directory."
		err_exit
	fi
fi

# Check if PARTSIZE variables are > 0
if [ -n "$KERNEL_PARTSIZE" ] ; then
	if [ ! "$KERNEL_PARTSIZE" -gt "0" ] ; then
		echo "KERNEL_PARTSIZE should be numeric greater than 0 (in MB)."
		err_exit
	fi
fi
if [ -n "$ROOTFS_PARTSIZE" ] ; then
	if [ ! "$ROOTFS_PARTSIZE" -gt "0" ] ; then
		echo "ROOTFS_PARTSIZE should be numeric greater than 0 (in MB)."
		err_exit
	fi
fi

# Check if custom functions exists and set the run variables
_prebuild=""
if [ -n "$BUILD_BEFORE" ] ; then
	if isFunction "$BUILD_BEFORE" ; then
		_prebuild="$BUILD_BEFORE"
	else
		echo "\$BUILD_BEFORE function \"$BUILD_BEFORE\" not found!"
		err_exit
	fi
fi
_posbuild=""
if [ -n "$BUILD_AFTER" ] ; then
	if isFunction "$BUILD_AFTER" ; then
		_posbuild="$BUILD_AFTER"
	else
		echo "\$BUILD_AFTER function \"$BUILD_AFTER\" not found!"
		err_exit
	fi
fi

[ -z "$MIRROR" ] && MIRROR="https://downloads.openwrt.org"
[ "$MAJOR_VERSION" -ge "18" ] && NAME="openwrt" || NAME="lede"
_EXT=".xz"
[ "$MAJOR_VERSION" -ge "24" ] && _EXT=".zst"
_VER="$VERSION-$TARGET-$SUB_TARGET"
_IMGBLD="$NAME-imagebuilder-$_VER.Linux-x86_64"
_URL="$MIRROR/releases/$VERSION/targets/$TARGET/$SUB_TARGET/$_IMGBLD.tar$_EXT"
case "$_EXT" in
	".bz")	_TAROPT="--bzip2"	; ;;
	".xz")	_TAROPT="--xz"		; ;;
	".gz")	_TAROPT="--gzip"	; ;;
	".zst")	_TAROPT="--zstd"	; ;;
	*)		_TAROPT=""			; ;;
esac

if ! wget -q --method="HEAD" "$_URL" ; then
	echo "Version $_VER not found! Please check the if that version exists." ; echo "URL: $_URL"
	err_exit
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
if [ -d "${_devdir}/root" -a -z "$FILES" ] ; then
	echo "Adding root files from \"${_devdir}/root\"..."
	tar -cvf - -C "${_devdir}" --exclude='.ipynb_checkpoints' "root" | tar -xf - -C "$TMP_DIR/"
# else copy the files if FILES is a directory
elif [ -d "$FILES" ] ; then
	echo "Adding root files from \"${FILES}\"..."
	mkdir -p "$TMP_DIR/root"
	tar -cvf - -C "$FILES" --exclude='.ipynb_checkpoints' "./*" | tar -xf - -C "$TMP_DIR/root/"
else
	echo "No aditional root files are being added."
fi

# copy package files if exists
if [ -d "${_devdir}/packages" ] ; then
	echo "Adding custom packages from \"${_devdir}/packages\"..."
	tar -cvf - -C "${_devdir}" --exclude='.ipynb_checkpoints' "packages" | tar -xf - -C "$TMP_DIR/"
else
	echo "No custom packages are being added."
fi

# Add SSH keys to ROOT if needed
if [ -n "$SSH_IMPORT_ID" ] ; then
	echo "Importing SSH IDs..."
	mkdir -p "$TMP_DIR/root"
	_ucidefaults="$TMP_DIR/root/etc/uci-defaults"
	_sshfile="$_ucidefaults/00-ssh-import-id"
	mkdir -p "$_ucidefaults"
	cat << "EOI" > "$_sshfile"
cat << "EOF" >> /etc/dropbear/authorized_keys
EOI
	for _id in $SSH_IMPORT_ID ; do
		ssh-import-id -o - $_id >> "$_sshfile"
	done
	cat << "EOI" >> "$_sshfile"
EOF
EOI
fi

# Save current directory
_PWD=$PWD

# --- Building ---

# Set build variables
_BUILD_COMMIT="NO-COMMIT"
_BUILD_BRANCH="NO-BRANCH"
if command -v git > /dev/null ; then
	_BUILD_COMMIT=$(git describe --always --tags --dirty --broken || echo "${_BUILD_COMMIT}")
	_BUILD_BRANCH=$(git branch --show-current || echo "${_BUILD_BRANCH}")
fi
_BUILD_TIME="$(date -u +'%Y%m%d-%H%M%S-%Z')"
_BUILD_TIME_ISO="$(date -Is)"
_BUILD_VER="${_VER}"
_BUILD_VERSION="${VERSION}"
_BUILD_MIRROR="${MIRROR}"
_BUILD_COMMAND="$0 $@"
_BUILD_USER="$(whoami)"
_BUILD_HOST="$(hostname)"
_BUILD_KERNEL="$(uname -s)-$(uname -r)"
_BUILD_KERNEL_ALL="$(uname -a)"

echo ; echo
echo "Making image for $_VER"
echo ; echo

# download openwrt builder
echo "Downloading $_IMGBLD"
wget -qO- --show-progress "$_URL" | tar -x $_TAROPT --directory $TMP_DIR/

echo "Configuring..."
# enter the image directory
cd $TMP_DIR/$_IMGBLD/

# Configure kernel build variables
[ -n "$KERNEL_PARTSIZE" ] && _KERNEL_PARTSIZE="CONFIG_TARGET_KERNEL_PARTSIZE=\"$KERNEL_PARTSIZE\""
[ -n "$ROOTFS_PARTSIZE" ] && _ROOTFS_PARTSIZE="CONFIG_TARGET_ROOTFS_PARTSIZE=\"$ROOTFS_PARTSIZE\""

# Backup and edit config file
_CFG_BKP=config.bkp
_CFG_OUT=config.out
_CFG_CFG=.config
[ ! -e "$_CFG_BKP" ] && (cp $_CFG_CFG $_CFG_BKP)
cp $_CFG_BKP $_CFG_CFG
# Remove sizes from config (if they are specified)
[ -n "$_KERNEL_PARTSIZE" ] && (grep --invert-match CONFIG_TARGET_KERNEL_PARTSIZE $_CFG_CFG > $_CFG_OUT ; mv $_CFG_OUT $_CFG_CFG)
[ -n "$_ROOTFS_PARTSIZE" ] && (grep --invert-match CONFIG_TARGET_ROOTFS_PARTSIZE $_CFG_CFG > $_CFG_OUT ; mv $_CFG_OUT $_CFG_CFG)
rm $_CFG_OUT 2> /dev/null

# run pre-build function if exists
[ -z "$_prebuild" ] || $_prebuild

# Set FILES if root exists
[ -d "$TMP_DIR/root" ] && FILES="$TMP_DIR/root"

# Copy packages if exists
[ -d "$TMP_DIR/packages" ] && cp -av "$TMP_DIR/packages"/* "packages/"

# Configure build variables
[ -n "$FILES" ] && _FILES="FILES=\"$FILES\""
[ -n "$PROFILE" ] && _PROFILE="PROFILE=\"$PROFILE\""
[ -n "$PACKAGES" ] && _PACKAGES="PACKAGES=\"$PACKAGES\""

echo "Making..."
# make the image
make clean
sh -ac "make image $_PROFILE $_FILES $_PACKAGES $_KERNEL_PARTSIZE $_ROOTFS_PARTSIZE"

# run post-build function if exists
[ -z "$_posbuild" ] || $_posbuild

# copy output
if directoryEmpty "$TMP_OUT" ; then
	cp -av bin/targets/$TARGET/$SUB_TARGET/* $OUT_DIR/
else
	cp -av $TMP_OUT/* $OUT_DIR/
fi

# do sha256sums in outdir
echo "Calculating checksums..."
cd $OUT_DIR
rm sha256sums 2> /dev/null
sha256sum * > sha256sums
cd $_PWD

# clear build dir
rm -r $TMP_DIR/$_IMGBLD
if ! directoryEmpty "$TMP_OUT" ; then
	rm -r $TMP_OUT/*
fi

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
