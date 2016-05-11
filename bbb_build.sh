#!/bin/sh

# Use buildroot to build a small and basic Linux system for the Beaglebone Black

SCRIPTDIR=$(dirname $(readlink -f $0))
. ${SCRIPTDIR}/settings.sh

# Download and "install" buildroot
if [ ! -d ${SCRIPTDIR}/build/buildroot-${BUILDROOT_VERSION} ]; then
    mkdir -p ${SCRIPTDIR}/build/dl && cd ${SCRIPTDIR}/build/dl
    wget -c https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.gz
    tar -C ${SCRIPTDIR}/build -xzf buildroot-${BUILDROOT_VERSION}.tar.gz
fi

# Copy config files into place
if [ ! -f ${SCRIPTDIR}/build/buildroot_config ]; then
    cp -rv ${SCRIPTDIR}/buildroot_config.example ${SCRIPTDIR}/build/buildroot_config
    cp -rv ${SCRIPTDIR}/kernel_config.example ${SCRIPTDIR}/build/kernel_config
fi

# Build the system
cd ${SCRIPTDIR}/build/buildroot-${BUILDROOT_VERSION}
cp ${SCRIPTDIR}/build/buildroot_config ./.config
# Choose whether or not to do the menu config stuff...
make menuconfig
cp ${SCRIPTDIR}/build/kernel_config ./kernel_config
echo "Making system through buildroot"
make > ${SCRIPTDIR}/build/buildroot.log 2>&1

# The image size in MiB
IMAGE_SIZE=64
IMAGE_NAME=${SCRIPTDIR}/build/buildroot-bbb.img

# Create an image file of appropriate size
dd if=/dev/zero of=${IMAGE_NAME} bs=1M count=${IMAGE_SIZE}

# Sorry if you were using any loop devices (Not all losetup supports option -D)!
sudo losetup -D > /dev/null 2>&1
sudo kpartx -av ${IMAGE_NAME}
DISK=`sudo losetup -a | grep -o -m 1 "/dev/loop[0-9].*${IMAGE_NAME}" | grep -o "/dev/loop[0-9]"`
echo "Using ${DISK} as the target device!"
if [ "N" = "N${DISK}" ]; then
    echo "No Target Found!"
    exit 1
fi

# The u-boot binaries we're going to boot from
IMAGES=${SCRIPTDIR}/build/buildroot-${BUILDROOT_VERSION}/output/images
uboot_MLO=${IMAGES}/MLO
uboot_img=${IMAGES}/u-boot.img

# See: http://elinux.org/Beagleboard:U-boot_partitioning_layout_2.0
# The above is a bit out of date though, as u-boot can now handle ext4 filesystems so long as
# journalling is disabled. Disabling journalling for a flash filesystem is a good idea anyway.
sudo dd if=${uboot_MLO} of=${DISK} count=1 seek=1 bs=128k
sudo dd if=${uboot_img} of=${DISK} count=2 seek=1 bs=384k

sudo parted -s ${DISK} mklabel msdos
sudo parted -s ${DISK} mkpart primary ext2 1M ${IMAGE_SIZE}

# I'm paranoid with syncs when working with images and SD Cards!
sync
sudo partprobe ${DISK}

sync
sudo mkfs.ext2 -O ^has_journal ${DISK}p1 -L rootfs
sudo mkdir -p /media/rootfs/
sudo mount ${DISK}p1 /media/rootfs/

# Create the root filesystem on the image
sudo tar -C /media/rootfs -xf ${IMAGES}/rootfs.tar

# Copy the bootloader support files
sudo cp -rv ${SCRIPTDIR}/boot/* /media/rootfs/boot

# Copy the devicetree's across to the
sudo mkdir -p /media/rootfs/boot/dtbs
sudo cp -rv ${IMAGES}/*.dtb /media/rootfs/boot/dtbs

sync
sudo umount /media/rootfs

# Remove the disk we've used
sudo losetup -d ${DISK}

pxz -zk ${SCRIPTDIR}/build/buildroot-bbb.img

exit 0
