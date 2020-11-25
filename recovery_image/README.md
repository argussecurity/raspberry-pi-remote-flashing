# Recovery Image

This README file contains instruction for building a Raspberry Pi Recovery Image.  

Each Raspberry Pi target is first flashed with a special image (*Recovery Image*) its SD-CARD.  
This image contains 3 partitions (original Raspberry Pi image consists of only two partitions):  

* u-boot
* boot
* root filesystem

| Number  | Start   | End     | Size    | Type     | File system  | Flags  
| --------|---------|---------|---------|----------|--------------|------|
 | 1     | 4194kB | 46.1MB | 41.9MB | primary | fat32       | boot, lba  
 | 2     | 46.1MB | 88.1MB | 41.9MB | primary | fat32       | lba  
 | 3     | 88.1MB | 10.8GB | 10.7GB | primary | ext3  
  
The Second and Third partition are empty.  
These partition are only place holders for the image the U-BOOT will flash.  

You can find in the repository a pre-built recovery image and jump to the [Flashing](#flashing) section.  
Please see the corresponding sections below for details.  

* [Recovery Image](#recovery-image)
  * [Prerequisites](#prerequisites)
  * [Building U-BOOT](#building-u-boot)
    * [Preparing U-BOOT](#preparing-u-boot)
    * [Build U-BOOT](#build-u-boot)
    * [Build Boot Script](#build-boot-script)
    * [Image Creation](#image-creation)
      * [Create an Empty Image](#create-an-empty-image)
      * [Format partitions](#format-partitions)
      * [Mount U-BOOT Partition and Copy Files](#mount-u-boot-partition-and-copy-files)
      * [Unount](#unount)
  * [Flashing](#flashing)
    * [Updating](#updating)
  * [Flashing Raspberry Pi using Recovery Image](#flashing-raspberry-pi-using-recovery-image)
  * [Settings](#settings)
  * [RPI U-BOOT Memory Address](#rpi-u-boot-memory-address)
  * [Known Issues](#known-issues)

## Prerequisites

* Ubuntu machine
* Tools:  
```sudo apt-get install make bison flex kpartx u-boot-tools```  
* ARM Compiler  
```sudo apt-get install gcc-arm-linux-gnueabi```  
* Raspberry Pi Model 3B/B+
* If you want to change the `u-boot` configuration, you will need also  
``` sudo apt-get install libncurses-dev ```

## Building U-BOOT

### Preparing U-BOOT  

We use version 2019.10 of `U-BOOT`, and made some patches to this version.  
When changing a version you may want/need to re-write those patches again.

```bash
wget https://github.com/u-boot/u-boot/archive/v2019.10.tar.gz
tar -xzf v2019.10.tar.gz  

# Apply Patches
cd u-boot-2019.10
for i in patches/u-boot/*.patch; do patch -p1 < $i; done
```

### Build U-BOOT

We build `U-BOOT` for the Raspberry Pi model 3B

```bash
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- rpi_3_32b_defconfig
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- -j$(nproc)
```

We already configured U-BOOT by patching **rpi_3_32b_defconfig** in previous step.  
If you want to configure it yourself, enable at least `CMD_TFTPPUT` , `CONFIG_NETCONSOLE`  
using `menuconfig` before running `make`.

```bash
make ARCH=arm menuconfig
```

### Build Boot Script

The boot script is the first thing U-BOOT runs after it loads.  
This script includes:

* Fetching an image from the TFTP server  
* Flashing the image on the SD Card  
* Preparing the boot commands  

U-BOOT script need to be prepared with `mkimage`.  
To build the u-boot boot script use this command:  

```bash
mkimage -A arm -O linux -T script -C none -n boot_script -d scripts/boot_script.txt boot.scr.uimg
```

### Image Creation

* Note: Values taken from 'meta-raspberry' layer for Yocto.  
  File: *meta-raspberrypi/classes/sdcard_image-rpi.bbclass*  
  
You can edit and use [calculator.sh](scripts/calclator.sh) in the *scripts* folder to get these commands with correct values.  

#### Create an Empty Image

We have three partition in our image:
Use the output lines from the [calculator.sh](scripts/calclator.sh) script to generate the right numbers (replacing the XXXXX):

```bash
sudo dd if=/dev/zero of=recovery.img bs=1024 count=0 seek=XXXXX
sudo parted -s recovery.img mklabel msdos
sudo parted -s recovery.img unit KiB mkpart primary fat32 XXXXX XXXXX
sudo parted -s recovery.img set 1 boot on
sudo parted -s recovery.img unit KiB mkpart primary fat32 XXXXX XXXXX
sudo parted -s recovery.img -- unit KiB mkpart primary ext3 XXXXX -1s
sudo parted recovery.img print
```

#### Format partitions  

First and second partition are FAT32, third partition is ext3  

```bash
sudo kpartx -av recovery.img

# get loop device name
LOOPDEV=`losetup --list | grep recovery.img | cut -d ' ' -f1 | cut -d '/' -f3`

sudo mkfs.vfat -F32 -n raspberry /dev/mapper/${LOOPDEV}p1
sudo mkfs.vfat -F32 -n raspberry /dev/mapper/${LOOPDEV}p2 
sudo mkfs.ext3 /dev/mapper/${LOOPDEV}p3
```

#### Mount U-BOOT Partition and Copy Files

We are copying official Raspberry Pi bootloader files, u-boot, scripts and env file.  

```bash
sudo mkdir -p /mnt/rpi
sudo mount /dev/mapper/${LOOPDEV}p1 /mnt/rpi

# Copy Rapsberry Pi Firmware files related to boot
wget https://github.com/raspberrypi/firmware/archive/1.20190925.tar.gz
tar -xzf 1.20190925.tar.gz
sudo cp -iv firmware-1.20190925/boot/{bootcode.bin,fixup.dat,start.elf} /mnt/rpi
sudo cp -iv config.txt /mnt/rpi

# Copy U-BOOT binary
sudo cp u-boot-2019.10/u-boot.bin /mnt/rpi/kernel.img
sudo cp -r boot.scr.uimg /mnt/rpi/
sudo cp -r env.txt /mnt/rpi/

sync  
```

#### Unount  

```bash
sudo umount /mnt/rpi
sudo kpartx -dv recovery.img
```

## Flashing

Insert SD card to your PC and find the device under /dev/sdX (you need to find X)  

```bash
sudo umount /dev/sdX?
sudo dd if=recovery.img of=/dev/sdX bs=4M  
sync  

# If you wish to append a raspberry pi image on this recovery:
sudo dd if=<Raspberry Pi Image> of=/dev/sda skip=1 seek=11 bs=4194304
```

### Updating

It is possible to update the U-BOOT only on online RPi device.  
The U-BOOT artifact is found under *artifacts/u-boot.bin*  
It is recommended also to update the bootscript even if you didn't made any changes.  
  
Example of updating Raspberry Pi at 10.0.0.111, user: root ; pass: root  

```bash
ssh root@10.0.0.111 mkdir -p /mnt/uboot ; mount /dev/mmcblk0p1 /mnt/uboot
scp artifacts/u-boot.bin artifacts/boot.scr.uimg root@10.0.0.111:/mnt/uboot/kernel.img
ssh root@10.0.0.111 sync ; umount /mnt/uboot
```

## Flashing Raspberry Pi using Recovery Image

The flashing process works by loading an image file into the RAM, and then writing it into the SD card.  
The RAM is about 1GB, so in order to be on the safe side, we will load maximum of 750MB.  
If we would like to flash image file which is larger than 750MB, we must split it, and flash it in parts.  
Any image file contains a partition table in its first 4MB.  
The SD card we are using is pre-flashed with our custom partition table.  
We only flash the raw partitions from the image file into our SD card, without overriding the partition table.  
On the first image file, we will skip the partition table, by skipping the first 4MB (0x400000 bytes).  
The U-BOOT is loaded in the lower addresses of the RAM, so we will load the image file to address `0x80000`, to keep the u-boot protected.  
The when flashing, the RAM address of the first image file will be 0x400000 + 0x80000 = 0x480000.  
For any additional image part file, the RAM address will be 0x80000 and up.  
  
These commands shows how to flash the first file only.  
They describe how to get an image from a TFTP server and flash it to the SD Card.  
For a splitted image file, you must calculate the offset in the SD card  
for each part image file. (Please use the script, and don't do it manually).  
The commands run during boot, on the client, from the compiled `boot.scr.uimg` script file.  
All numbers in the commands, are in Hexadecimal form (even if you omit the prefix '0x')  
`tftpboot` command uses RAM address in bytes.  
mmc command uses RAM address in bytes, and SD card address in blocks (1 block = 512 bytes = 0x200 bytes)  

```console
setenv serverip 10.64.96.112  # TFTP server address
setenv ipaddr 10.64.96.135    # target RPi ip
saveenv  

# Load rpi_image_part_0 file from server into the RAM, into address 0x80000
tftpboot 0x00080000 ${serverip}:rpi_image_part_0   

# Write 0x76000 blocks into SD card, address 0x16000 (blocks), from RAM address 0x480000 (bytes)
mmc write 0x480000 0x16000 0x76000 
```

All the address were calculated using the [calculator.sh](scripts/calclator.sh) script  
** In the example above, assuming image size is 0xec00000 bytes - converted to blocks = 0x76000

## Settings

The Raspberry Pi server, the target IP address, and the flashed image name  
can be set by editing the file **env.txt** in the fist partition of the Recovery SD Card.  
You should at least change the *ipaddr* (the IP address of the Raspberry Pi Target).  
The *serverip* is the Raspberry Pi Server IP address.  

## RPI U-BOOT Memory Address

On start up, the U-BOOT relocate itself to *relocaddr*.  
This is the higher end of the memory address we can use when downloading an image from a TFTP server.  
Practically, we use RAM addresses from 0x00080000 to *relocaddr*  

```console
arch_number = 0x00000000  
boot_params = 0x00000100  
DRAM bank   = 0x00000000  
-> start    = 0x00000000  
-> size     = 0x3b400000  
baudrate    = 115200 bps  
TLB addr    = 0x3b3f0000  
relocaddr   = 0x3b36b000  
reloc off   = 0x3b363000  
irq_sp      = 0x3af66ec0  
sp start    = 0x3af66eb0  
FB base     = 0x00000000
```

## Known Issues

* Sometimes U-BOOT gives ```Rx: failed to receive: -5``` error when trying to fetch a file.  
This usually happens when an HDMI cable is connected.  
Disconnecting the cable usually solves this (you can still see the console prints using a Serial connection)  
* Yellow screen when booting - this can be solved by disabling **bcm2708_fb_init** module in the boot params.  
This solution is currently applied in the boot script.  
