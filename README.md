# Raspberry Pi Remote Flashing

This README file contains description about the Raspberry Pi Remote Flashing system.

- [Raspberry Pi Remote Flashing](#raspberry-pi-remote-flashing)
  - [Subdirectories](#subdirectories)
  - [General System Overview](#general-system-overview)
  - [Flashing an Image Flow](#flashing-an-image-flow)

## Subdirectories

* [Recovery Image](recovery_image)  
* [Raspberry Pi Server](server)  
* [Flashing Script](scripts)  

## General System Overview

A system should consist one of Raspberry Pi Server, controlling at least one Raspberry Pi target.  
The limitation of how many targets are connected to one server is the number of *GPIO* and *GND* pins available the Raspberry Pi Server.  
  
All the available flashed targets are stored in a csv file.  
We store the MAC addresses, IP addresses and which server's GPIO is controlling each Raspberry Pi.
  
The Raspberry Pi server role is to hard-reset the flashed target before flashing,  
and provide it an image by a TFTP server.
  
Each Raspberry Pi target is first flashed with a special image (*Recovery Image*) on its SD-CARD.  
This image contains 3 partitions (original Raspberry Pi image consists of only two partitions):  

* u-boot
* boot
* root filesystem

When the target Raspberry Pi boots, it loads an additional bootloader called U-BOOT instead of the linux kernel.  
U-BOOT then looks for an image to flash on the Raspberry Pi server, inside a folder named by its MAC address.  
If it finds an image, the U-BOOT starts downloading it to the Raspberry Pi's RAM.
  
After the download is completed, it then starts overwriting the second and third partition  
of the SD CARD with the image which was just downloaded to RAM.  
  
There is a precise address calculations here, and the first partition  
scheme should be the same for both the image being flashed and the Recovery Image.  

## Flashing an Image Flow

* User Copies the **New Image** to the Raspberry Pi Server  
* User Copies [Flashing Scripts](scripts) and [Raspberry Pis Database](scripts/db)  
* User executes the Flashing Script on the server, and provides the IP address of the target Raspberry Pi.  
* Flashing Script looks for the Raspberry Pi target on the Database.  
  When found:  
  * Place the image into the TFTP file server folder, under a folder name  
    with the MAC address of the target,  and rename it to rpi_image_part_0.
  * If the image file is bigger than 750MB, it splits it to parts, with name format rpi_image_part_<part#>
  * Reset the target by pulling the *RESET* gpio *LOW*.
* The target Raspberry Pi boots and loads U-BOOT from the fist partition,  
  loads a boot script, and looks for a an image on the Raspberry Pi Server TFTP file server.
  * When found, it starts the flashing process:
    * Load the image part file from TFTP server to RPI RAM
    * Flash the image part file from RAM to MMC0 (SD CARD)
    * Repeat the two steps above for each part file in the TFTP server
    * Create a file on the TFTP server with the name OK or FAILED.  
         The content of this file is binary data with the bytes flashed on the MMC so we can use it later for flashing validation.
    * Note: The first image file is NOT flashed completely. The script skip the first 4MB, because they contain the partition table.
  * When not found - it skips this step
* The U-BOOT reads the the boot commands from a file called **cmdline.txt** on the second partition,  
 add a new variable to the command line with the new position of the the `rootfs` (it is now on the third partition),  
 load the device tree and kernel from the second partition, and boots the kernel.
