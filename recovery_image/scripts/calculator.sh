#!/usr/bin/env bash

# SPDX-License-Identifier: GPL-2.0 #
# (C) Copyright Argus Cyber Security Ltd
#  All rights reserved

#######################################################################################################################
# Script Name   :   Recovery Image Offsets Calculator
# Description   :   Calculates offsets according to pre-defines constants
#                   and provides commands for generating a Recovery Image file.
# Args			:
# Date			:   23/11/2020
# Author		:   Itay Sperling
# Email         :   itay.sperling@argus-sec.com
#######################################################################################################################

# U-BOOT Settings
LOADADDR="0x00080000"

# Recovery Image Settings
SDIMG="recovery.img"
# Use an uncompressed ext3 by default as rootfs
SDIMG_ROOTFS_TYPE="ext3"
ROOTFS_PT_SIZE="10485760" #10GB
# Boot partition size [in KiB] (will be rounded up to IMAGE_ROOTFS_ALIGNMENT)
BOOT_PART_SIZE="40960"
# Set alignment to 4MB [in KiB]
IMAGE_ROOTFS_ALIGNMENT="4096"

BOOT_PART_SIZE_ALIGNED=$(( BOOT_PART_SIZE + IMAGE_ROOTFS_ALIGNMENT - 1 ))
BOOT_PART_SIZE_ALIGNED=$(( BOOT_PART_SIZE_ALIGNED - (( BOOT_PART_SIZE_ALIGNED % IMAGE_ROOTFS_ALIGNMENT)) ))
SDIMG_SIZE=$(( IMAGE_ROOTFS_ALIGNMENT + BOOT_PART_SIZE_ALIGNED + ROOTFS_PT_SIZE ))

UBOOT_PARTITION_START="${IMAGE_ROOTFS_ALIGNMENT}"
UBOOT_PARTITION_END=$(( BOOT_PART_SIZE_ALIGNED + IMAGE_ROOTFS_ALIGNMENT ))
BOOT_PARTITION_END=$(( UBOOT_PARTITION_END + BOOT_PART_SIZE_ALIGNED ))

echo "## Creating filesystem with Boot partition ${BOOT_PART_SIZE_ALIGNED} KiB and RootFS $((ROOTFS_PT_SIZE)) KiB ##"
echo ""
echo "sudo dd if=/dev/zero of=${SDIMG} bs=1024 count=0 seek=${SDIMG_SIZE}"
echo "sudo parted -s ${SDIMG} mklabel msdos"
echo "sudo parted -s ${SDIMG} unit KiB mkpart primary fat32 ${UBOOT_PARTITION_START} ${UBOOT_PARTITION_END}"
echo "sudo parted -s ${SDIMG} set 1 boot on"
echo "sudo parted -s ${SDIMG} unit KiB mkpart primary fat32 ${UBOOT_PARTITION_END} ${BOOT_PARTITION_END}"
# Create rootfs partition to the end of disk
echo "sudo parted -s ${SDIMG} -- unit KiB mkpart primary ${SDIMG_ROOTFS_TYPE} ${BOOT_PARTITION_END} -1s"
echo "sudo parted ${SDIMG} print"
echo ""
echo "## Append Raspberry Pi image to an SD-CARD with a recovery.img with this command:"
echo ""
BS=$(( UBOOT_PARTITION_START * 1024 ))
echo "sudo dd if=rpi.img of=/dev/sdX skip=1 \
seek=$(( UBOOT_PARTITION_END / UBOOT_PARTITION_START )) \
bs=${BS}"

echo -e "\n\nU-BOOT\n----------"
MMC_WRITE_ADDRESS=$(($((LOADADDR)) + $((BS))))

# convert to hex
printf -v MMC_WRITE_ADDRESS "%x ${MMC_WRITE_ADDRESS}"
echo "tftp ${LOADADDR} <server ip>:rpi.img"
echo "mmc write 0x$MMC_WRITE_ADDRESS 0x16000 0x76000"
