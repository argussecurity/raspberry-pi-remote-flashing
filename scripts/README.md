# Server Scripts
This README file contains instruction for using Raspberry Pi Flasher script
- [Server Scripts](#server-scripts)
  - [Prerequisites](#prerequisites)
  - [Instructions](#instructions)
  - [Adding / Removing Raspberry Pi Targets](#adding--removing-raspberry-pi-targets)
  - [Exit Codes](#exit-codes)

## Prerequisites

* IP Address of the target Raspberry Pi.
  You can view all the available Raspberry Pis in their DB files under [db](db/)
* ARM Compiler

```bash
sudo apt-get install gcc-arm-linux-gnueabi
```

* `ncb` from U-Boot sources built for ARM

```bash
arm-linux-gnueabi-gcc <u-boot sources>/tools/ncb.c -o ncb
```

## Instructions

* Copy the image you want to flash to the Raspberry Pi Flashing Server (Currently, IP Address: 10.64.100.99)  
* Copy **flash_pi.sh** to the Raspberry Pi Flashing Server  
* Copy **rpi_DB.sh** to the Raspberry Pi Flashing Server  
* Run the script remotely:  (Username: `pi`, Password: `raspberry`)

```bash
ssh pi@<RPI SERVER> "<PATH_TO_SCRIPT>/flash_pi.sh -i <IMAGE> -a <RPI TARGET/TARGET>"
```

## Adding / Removing Raspberry Pi Targets

* Add to the file **rpi_DB.csv** a new row, comma separated, in this format:  
```<MAC ADDRESS>,<IP ADDRESS>,<RESET GPIO>```  
* For removing, delete the CSV row with the target Raspberry Pi.  

## Exit Codes

| Code    | Description
| --------|-----------
| 0       | Remote Flashing Finished Successfully.
| 1       | Flashing Finished but target is not responding.
| 2       | Received FAILED error from U-BOOT
| 3       | Flashing timeout
| 4       | Flashed bytes does not match image size
| 6       | DB file not found
| 7       | RPI Image does not exist on the server
| 8       | Target not found in DB
| 9       | Script usage error