mountpoints=""

## Mapping of fs-types
declare -A fstypes
fstypes=(["Linux"]="" ["W95 FAT32 (LBA)"]="vfat")

function set_ssh_permissions() {
  local v_username="${1:?Missing username}"
  local user_uid=$(stat --printf "%u" ${fs_base}/home/${v_username})
  local user_gid=$(stat --printf "%g" ${fs_base}/home/${v_username})

  chown -R ${user_uid}:${user_gid} "${fs_base}/home/${v_username}/.ssh"
  chmod -R 700 "${fs_base}/home/${v_username}/.ssh"
}

function mount_filesystem() {
  local image=$1
  local device=$2
  local target=$3

  if [ ! -f $image ]; then
    echo "Source image for mount ($target) could not be found"
    return 1
  fi
  if [ ! -d $target ]; then
    echo "Target directory for mount ($target) could not be found. Creating it..."
    mkdir -p $target
  fi
  startblock=$(fdisk -l -o device,start $v_targetimage | grep ^$device | cut -d ' ' -f 2- | sed -e 's/^\ *//')
  fssize=$(fdisk -l -o device,sectors $v_targetimage | grep ^$device | cut -d ' ' -f 2- | sed -e 's/^\ *//')
  fstype=$(fdisk -l -o device,type $v_targetimage | grep ^$device | cut -d ' ' -f 2- | sed -e 's/^\ *//')

  fstype=${fstypes["$fstype"]}
  offset=$((startblock * 512))
  sizelimit=$((fssize * 512))
  sudo mount -o offset=$offset,sizelimit=$sizelimit ${fstype:+-t $fstype} "$image" "$target"
  if [ $? -ne 0 ]; then
    echo "Error while mounting $image to $target"
    echo "Failed command: sudo mount -o offset=$offset,sizelimit=$sizelimit ${fstype:+-t $fstype} \"$image\" \"$target\""
    return 1
  else
    echo "Mounted $image with offset=$offset and sizelimit=$sizelimit to $target"
  fi
  mountpoints="$mountpoints $target"
}

function unmout_filesystem() {
  local mountpoint=$1
  while [ $(fuser -Mm "${mountpoint}" 2>/dev/null | wc -w) -gt 0 ]; do
    echo "Warning: There are active processes on the filesystem mounted at $mountpoint:"
    fuser -Mm $mountpoint
    echo "Warning: Trying to kill processes"
    fuser -Mk $mountpoint
  done
  sync -f "${mountpoint}"
  umount -f $mountpoint
}

function get_filesystems() {
  local image=$1
  LANG=C fdisk -l -o device "$image" | sed -n '/^Device$/,$p' | tail -n +2
}
