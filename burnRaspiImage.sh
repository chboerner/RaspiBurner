#!/usr/bin/env bash
# shellcheck disable=SC2086
# shellcheck disable=SC2046
# shellcheck disable=SC2162

# exit immediately on error
#set -e

# Some basic configuration
## Filesystem type for secondary partition. Used by parted and mkfs.
## If empty FS will not be formatted. Supported values are ext4 and xfs.
fstype=""

usage() {
  cat <<EOF
Usage $0 <options>

-D <disk device>      Device name with RaspberryPiOS. Only device, not file systems!
                      Ex. /dev/sdd instead of /dev/sdd1
-I <image>            RaspberryPiOS image which should be written to the disk.
-S <size>             Size of secondary partition in Gigabytes (created at end of disk)

EOF
  exit ${1:-0}
}

while getopts D:I:H:S:h opt
do
   case $opt in
       D) v_disk=$OPTARG
         ;;
       I) v_image=$OPTARG
         ;;
       S) v_secondary_partition=$OPTARG
         ;;
       h) usage
         ;;
       *) usage 1
         ;;
   esac
done

[ $# -eq 0 ] && usage 1

if [ ! -f "$v_image" ]; then
	echo "$v_image could not be found"
	exit 1
fi

if [[ "$USER" != "root" ]]; then
  echo "Please run this command with sudo and root permissions."
  exit 1
fi

echo "Disk information:"
parted -s $v_disk unit GB print
[ $? -ne 0 ] && exit

read -t 30 -p "Are you sure you want to write $v_image to $v_disk? This will also wipe existing filesystems on the disk. ('yes'/'no'): " REPLY
if [ "$(echo "$REPLY" | tr '[:upper:]' '[:lower:]')" != "yes" ]; then
	echo "Answer was not 'yes'. Aborting operation..."
	exit
fi
echo
unset REPLY

if [ $(lsblk ${v_disk} --noheadings --raw | grep -c "part\s*$") -gt 0 ]; then
  echo "WARNING: ${v_disk} is not clean. Cleaning disk..."
  sfdisk --delete $v_disk
fi

echo "Writing image to disk"
dd if="${v_image}" of=${v_disk} oflag=sync status=progress bs=4M

echo "Waiting for DiskIO to settle..."
sync ${v_disk}
sleep 2

echo "Image written to disk."

if [ -n "$v_secondary_partition" ]; then
  if [ "$(echo -n $v_secondary_partition | tr -d '[:alnum:]' | wc -c)" -ne 0 ]; then
    echo "Found invalid characters in size string"
    exit 1
  fi

  v_secondary_partition=$(echo $v_secondary_partition | tr -d '[:space:]')
  unit=$(echo $v_secondary_partition | tr -d '[:digit:]' | tr '[:lower:]' '[:upper:]')
  fssize=$(echo $v_secondary_partition | tr -d '[:alpha:]')

  case $unit in
    K) unit=KB ;;
    M) unit=MB ;;
    G) unit=GB ;;
    T) unit=TB ;;
  esac

  # Check if there is enough space left at end of the disk
  disk_free=$(parted --machine --script $v_disk unit ${unit} print free | grep ":free" | tail -n 1 | cut -d ':' -f 4 | tr -d '[:alpha:]')
  if [ $((disk_free-fssize)) -lt 0 ]; then
    echo "Not enough free space left on disk for a $v_secondary_partition partition. Maximum space left is ${disk_free}${unit}"
    exit 1
  fi

  # Get total disk size - required to calculate starting position of new partition
  EOP=$(parted --machine --script $v_disk unit ${unit} print free | grep ":free" | tail -n 1 | cut -d ':' -f 3 | tr -d '[:alpha:]')
  # Calculate starting position of new partition
  BOP=$(( (EOP-fssize) ))
  # Create partition
  parted --align=optimal --script -- $v_disk mkpart primary ${fstype} ${BOP}${unit} '100%'
  if [ -n "$fstype" ]; then
    # Get name of newly created partition
    fname=$(fdisk -l $v_disk | tail -n 1 | awk '{print $1}')
    # Create filesystem on partition
    mkfs.${fstype} $fname
  fi
fi
