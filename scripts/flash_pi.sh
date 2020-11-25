#!/usr/bin/env bash

# SPDX-License-Identifier: GPL-2.0 #
# (C) Copyright Argus Cyber Security Ltd
#  All rights reserved

#######################################################################################################################

# Script Name   :   Flash Raspberry Pi
# Description   :   This script receives path of image on the fs, and ip address of a target
#                   that should be flashed with a new image.
#                   Then, it looks for the MAC address and the RESET gpio on db/<HOSTNAME>.csv file,
#                   creates a directory under /srv/tftp with which its name is the MAC address.
#                   If the image is bigger than 750MB, it splits it to 750MB parts,
#                   with name format 'rpi_image_part_<#>', and put them in this folder.
#                   If the image is smaller than 750MB, it moves the image to this folder
#                   and renames it to 'rpi_image_part_0'. Then, it resets the Target Raspberry Pi
#                   and wait for a ping or 10 minutes timeout.
#                   After ping received / timeout event occurred, delete the 'rpi.img' from the folder.
# Args          :   -i <image file> -a <target ip address>
# Date          :   23/11/2020
# Author        :   Itay Sperling
# Email         :   itay.sperling@argus-sec.com
#######################################################################################################################


# Paths
SCRIPT=$(realpath $0)
SCRIPT_PATH=$(dirname $SCRIPT)
TFTP_BASE_FOLDER="/srv/tftp/"

cd "${SCRIPT_PATH}" || return
source exit_codes.sh

# Globals
PI_DB=""
PATH_TO_IMAGE=""
SLAVE_IP_ADDRESS=""
SLAVE_MAC_ADDRESS=""
SLAVE_RESET_GPIO=""
TFTP_FOLDER=""
IMG_SIZE=0

usage() {
    echo "usage: $0 -i <path to image> -a <ip address>"
    exit "${USAGE_ERROR}"
}

# Remove the image from tftp server
clean_tftp() {
    rm -rf "${TFTP_FOLDER}"
}

# Kill netconsole server instance
kill_netconsole_server() {
    kill $(ps -o pid= --ppid=${NETDEV_PROC})
}

verify_flashed_image_size() {
    # Compare the flashed bytes count against the image size
    WRITTEN_BYTES=$(hexdump -n 4 -e '"%u"' ${TFTP_FOLDER}/OK)

    echo -e "Image Size (without PT):\t $IMG_SIZE"
    echo -e "Flashed Bytes:\t $WRITTEN_BYTES"

    if [[ $IMG_SIZE -ne $WRITTEN_BYTES ]]; then
        echo "Flashed bytes does not match image size"
        echo "Flashing Failed."
        clean_tftp
        kill_netconsole_server
        exit "${FLASHED_SIZE_MISMATCH}"
    fi
}

script_inputs_check() {
    # Chcek if params not empty
    if [ -z "${PATH_TO_IMAGE}" ] ||
        [ -z "${SLAVE_IP_ADDRESS}" ]; then
        echo "One or more paramaters are empty."
        usage
    fi

    # Check if image exists on fs
    if [ ! -f "$PATH_TO_IMAGE" ]; then
        echo "$PATH_TO_IMAGE does not exist"
        exit "${MISSING_IMAGE_FILE}"
    fi
}

extract_pi_from_db() {
    PI_DB="${SCRIPT_PATH}/db/$(cat /etc/hostname).csv"
    echo "Using DB: $PI_DB"

    # Read CSV databse and look for the target details
    OLDIFS=$IFS
    IFS=','
    [ ! -f $PI_DB ] && {
        echo "$PI_DB file not found"
        exit "${DB_FILE_MISSING}"
    }
    while read mac ip reset_io; do
        if [ $ip == $SLAVE_IP_ADDRESS ]; then
            SLAVE_MAC_ADDRESS=$mac
            SLAVE_RESET_GPIO=$reset_io
            echo "Target Found:"
            echo -e "IP:\t ${SLAVE_IP_ADDRESS}"
            echo -e "MAC:\t ${SLAVE_MAC_ADDRESS}"
            echo -e "GPIO:\t ${SLAVE_RESET_GPIO}"
            break
        fi
    done <$PI_DB
    IFS=$OLDIFS

    if [[ $SLAVE_MAC_ADDRESS == "" ]]; then
        echo "Target not found in DB"
        exit "${TARGET_NOT_FOUND}"
    fi
}

prepare_tftp() {
    TFTP_FOLDER="${TFTP_BASE_FOLDER}/${SLAVE_MAC_ADDRESS}"

    # Remove leftovers (this folder should be empty)
    clean_tftp

    # Create a folder with the MAC address name
    mkdir -p "${TFTP_FOLDER}"

    # Minimum size to split is 750MB
    minimum_size_to_split=786432000
    actualsize=$(stat -c%s "${PATH_TO_IMAGE}")
    echo "actualsize = $actualsize"
    # PT takes 4MB, we won't flash it, and so no need to calculate it as well
    ((IMG_SIZE = actualsize - 4194304))
    echo "IMG_SIZE = $IMG_SIZE"
    if [ $actualsize -ge $minimum_size_to_split ]; then
        # Split the big image to 750MB smaller parts, and put them into this folder
        echo "Splitting image file to parts of $minimum_size_to_split bytes"
        split -d -a 1 --bytes=${minimum_size_to_split} "${PATH_TO_IMAGE}" "/srv/tftp/${SLAVE_MAC_ADDRESS}/rpi_image_part_"
        rm -f "${PATH_TO_IMAGE}"
    else
        # Move the image to this folder
        mv "${PATH_TO_IMAGE}" "/srv/tftp/${SLAVE_MAC_ADDRESS}/rpi_image_part_0"
    fi
    chmod -R 777 "${TFTP_FOLDER}"
}

toggle_gpio() {
    # Hard reset the target
    gpio mode "${SLAVE_RESET_GPIO}" out
    gpio write "${SLAVE_RESET_GPIO}" 0
    sleep 0.5
    gpio write "${SLAVE_RESET_GPIO}" 1
    sleep 0.5
    gpio mode "${SLAVE_RESET_GPIO}" tri # (disconencted from system)
}

start_flashing() {
    echo "Flashing Started."
    echo ""

    echo "Starting a Netconsole server:"
    # Open netconsole
    ./netconsole "${SLAVE_IP_ADDRESS}" &
    NETDEV_PROC=$!
    sleep 0.5
    echo ""

    toggle_gpio

    # At this stage the target U-BOOT should try to
    # fetch the image from the server and flash it.

    # The target should put a file called "FAIL" or "OK" under ${SLAVE_MAC_ADDRESS}.
    # The content of this file is the amount bytes the U-BOOT flashed

    # Look for "OK" or "FAIL"

    # We should expect a ssh connection under 10 minutes
    # The calculation here is to get 6 minutes per 250MB
    # (every count adds 5 seconds, so for 250MB we get count = 72)
    ((count = IMG_SIZE / 3640888))
    while [[ $count -ne 0 ]]; do
        if [ -f "${TFTP_FOLDER}/FAIL" ]; then
            echo "FAILED"
            clean_tftp
            kill_netconsole_server
            exit "${U_BOOT_FAILED_ERR}"
        fi

        if [ -f "${TFTP_FOLDER}/OK" ]; then
            echo " OK"
            echo ""
            verify_flashed_image_size
            break
        fi
        ((count = count - 1)) # So we don't go forever.
        sleep 5               # Try again in 5 seconds
    done

    if [[ $count -eq 0 ]]; then
        #timeout error
        echo "Flashing timeout"
        clean_tftp
        kill_netconsole_server
        exit "${FLASHING_TIMEOUT}"
    fi

    echo ""
    echo "Flashing Finished."
    sleep 6 # This sleep is for not disturbing the u-boot logs with prints
    echo ""
    echo -e "Waiting for board to become online \c"

    # We should expect a ssh connection under 3 minutes
    ((count = 36))
    while [[ $count -ne 0 ]]; do
        echo -e ".\c"
        nc -zw 1 "${SLAVE_IP_ADDRESS}" 22 >/dev/null # Try to reach port 22 (ssh)
        rc=$?
        if [[ $rc -eq 0 ]]; then
            break
        fi
        ((count = count - 1)) # So we don't go forever.
        sleep 5               # Try again in 5 seconds
    done

    exit_code="${FLASHING_SUCCEEDED}"
    if [[ $count -ne 0 ]]; then
        echo " Target is up."
        echo ""
        echo "Remote Flashing Finished Successfully."
    else
        echo " Timeout."
        echo ""
        echo "Flashing Finished but target is not responding."
        exit_code="${TARGET_NOT_RESPONDING}"
    fi

    clean_tftp
    kill_netconsole_server
    exit $exit_code
}

while getopts ":i:a:h:" args; do
    case "${args}" in
    i)
        PATH_TO_IMAGE=${OPTARG}
        ;;
    a)
        SLAVE_IP_ADDRESS=${OPTARG}
        ;;
    h)
        usage
        ;;
    *)
        usage
        ;;
    esac
done

script_inputs_check
extract_pi_from_db
prepare_tftp
start_flashing
