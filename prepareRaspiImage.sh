#!/usr/bin/env bash

# exit immediately on error
set -e

# Defaults
scripts_basedir="$(dirname $(readlink -e "$0"))"
working_basedir="$(pwd)"

v_userhome=$(eval echo "~${SUDO_USER}")
v_sshkey="${v_userhome}/.ssh/id_rsa"
v_user_pi=pi
v_user_new=christian

v_autoprovision=false
v_provision_gh_repo=""
v_provision_gh_key=""
v_provision_basedir="/provision"
v_provision_playbook=""

source ${scripts_basedir}/shared_functions.sh

usage() {
  cat <<EOF
Usage $0 <options>

Image options:
-I <disk image>           Raw OS Image with RasperryPiOS that should be modified.
-T <target image>         This option creates a copy of Raw OS image to work on it. Default is to work on the original.

RaspberryPi settings:
-H <hostname>             Hostname to be configured for this OS image without domain portion
-s <ssh key>              Use this ssh key instead of the configured default ($v_sshkey) for user $v_user_new
-u <username>             New custom username on the RaspberryPi. Defaults to $v_user_new
-d <DHCP Static file>     Use this file to gather static IP settings for DHCPcd conf.
                          This file will be __appended__ to /etc/dhcpcd.conf and stored as /boot/fixed.ip for the
                          provisioner.

Auto provision options:
-r <GitHub Repository>    GitHub Repository containing the provisioning code
-k <GitHub Deploy Key>    Deployment key to be used for private/protected repositories
-p <Provision base dir>   Directory where the GitHub repository is cloned (default: $v_provision_basedir)
-P <Playbook File>        Ansible playbook file that should be run for initial provisioning
-a                        Enable Ansible Autoprovisioning after boot (default: $v_autoprovision)
                          Requires at least the GitHub repository to be named.

EOF
  exit ${1:-0}
}

while getopts I:T:H:s:r:k:p:P:ad:u:h opt; do
  case $opt in
  I)
    v_sourceimage=$OPTARG
    ;;
  T)
    v_targetimage=$OPTARG
    ;;
  H)
    v_hostname=$OPTARG
    ;;
  s)
    v_sshkey=$OPTARG
    ;;
  r)
    v_provision_gh_repo=$OPTARG
    ;;
  k)
    v_provision_gh_key=$OPTARG
    ;;
  p)
    v_provision_basedir=$OPTARG
    ;;
  P)
    v_provision_playbook=$OPTARG
    ;;
  a)
    v_autoprovision=true
    ;;
  d)
    v_dhcpcd_file=$OPTARG
    ;;
  u)
    v_user_new=${OPTARG::?Missing username}
    ;;
  h)
    usage
    ;;
  *)
    usage 1
    ;;
  esac
done

## End if no options where given.
[ $# -eq 0 ] && usage 1

function cleanup() {
  set +e
  for mountpoint in $mountpoints; do
    echo "Unmounting and removing mount point $mountpoint"
    unmout_filesystem $mountpoint
    rm -r $mountpoint
  done
}
trap cleanup EXIT

function check_if_sudo() {
  if [ $(id -u) -ne 0 ]; then
    echo "You need to run this script with sudo. Otherwise it's not possible to modify content in the image that belongs to the root user."
    exit 1
  fi
  if [ -z "$SUDO_UID" ]; then
    echo "Warning: you're running this script as logged in root. This is not recommended."
  fi
}

function prepare_bootfs() {
  local fs_base=$1
  echo "Preparing boot filesystem"

  echo "Enabling SSH"
  touch "$fs_base/ssh"

  if [ -n "$v_dhcpcd_file" ]; then
    echo "Copying dhcpcd static IP configuration to /boot/fixed.ip"
    if [ ! -f "$v_dhcpcd_file" ]; then
      echo "ERROR: $v_dhcpcd_file could not be found."
      exit 1
    fi
    cp "$v_dhcpcd_file" ${fs_base}/fixed.ip
  fi

  # This will rename user pi to the new username and disable password login
  if [ -n "$v_user_new" ]; then
    echo "Setting new username to $v_user_new ($v_user_pi will be renamed on first boot)"
    echo "$v_user_new:!" > ${fs_base}/userconf
  fi
}

function prepare_rootfs() {
  local fs_base=$1
  echo "Preparing root filesystem"

  user_uid=$(stat --printf "%u" ${fs_base}/home/$v_user_pi)
  user_gid=$(stat --printf "%g" ${fs_base}/home/$v_user_pi)

  echo "Copying SSH public key from $v_sshkey to user ${v_user_pi}"
  mkdir -p "${fs_base}/home/${v_user_pi}/.ssh"
  ssh-keygen -y -f "${v_sshkey}" >"${fs_base}/home/${v_user_pi}/.ssh/authorized_keys"
  set_ssh_permissions ${v_user_pi}

  echo "Enabling PubKey authentication for SSH"
  sed -i -e 's/^.*PubkeyAuthentication.*$/PubkeyAuthentication yes/' "${fs_base}/etc/ssh/sshd_config"

  if [ -n "$v_hostname" ]; then
    echo "Setting hostname"
    echo "$v_hostname" >"${fs_base}/etc/hostname"
  else
    echo "No hostname set. Skipping configuration."
  fi

  if [ -n "$v_dhcpcd_file" ]; then
    echo "Appending dhcpcd static IP configuration to /etc/dhcpcd.conf"
    if [ ! -f "$v_dhcpcd_file" ]; then
      echo "ERROR: $v_dhcpcd_file could not be found."
      exit 1
    fi
    cat "$v_dhcpcd_file" >> ${fs_base}/etc/dhcpcd.conf
  fi


  echo "Setting systemd default.target to multi-user.target"
  cd "${fs_base}/etc/systemd/system" &&
    ln -nsf /lib/systemd/system/multi-user.target default.target &&
    cd "${working_basedir}"

  echo "Disable Console AutoLogin"
  [ -f "${fs_base}/etc/systemd/system/getty@tty1.service.d/autologin.conf" ] && rm "${fs_base}/etc/systemd/system/getty@tty1.service.d/autologin.conf"

  if [ -n "$v_provision_gh_repo" ]; then
    echo "Configuring GitHub repository $v_provision_gh_repo as provisioner."

    echo "Writing /.provision.conf"
    echo "github_repo=$v_provision_gh_repo" >"${fs_base}/.provision.conf"
    echo "provision_basedir=$v_provision_basedir" >>"${fs_base}/.provision.conf"
    echo "provision_playbook=$v_provision_playbook" >>"${fs_base}/.provision.conf"
    echo "provision_user=${v_user_pi}" >>"${fs_base}/.provision.conf"

    if [ -n "$v_provision_gh_key" ]; then
      keyname=$(basename $v_provision_gh_key)
      echo "Copying GitHub deploy key"
      cp "$v_provision_gh_key" "${fs_base}/home/$v_user_pi/.ssh/$keyname"
      echo "Setting ssh config to use the deploy key with GitHub"
      echo -e "Host github.com\n  User git\n  IdentityFile /home/$v_user_pi/.ssh/$keyname" >>"${fs_base}/home/$v_user_pi/.ssh/config"
      set_ssh_permissions $v_user_pi
    else
      echo "No GitHub deploy key specified. The provisioner GitHub repository must be set to public, otherwise cloning the repo will fail."
    fi

    if [[ $v_provision_gh_repo =~ github.com:.*.git$ ]]; then
      echo "Adding GitHub ssh fingerprint to known_hosts file"
      ssh-keyscan github.com >> "${fs_base}/home/$v_user_pi/.ssh/known_hosts"
      set_ssh_permissions $v_user_pi
    fi

    echo "Copying provisioner service file"
    cp -va $scripts_basedir/files/base_provision.service ${fs_base}/lib/systemd/system/
    cp -va $scripts_basedir/files/base_provision.sh ${fs_base}/
    chmod +x ${fs_base}/base_provision.sh

    if $v_autoprovision; then
      echo "Linking provision oneshot service as wanted by multi-user"
      cd "${fs_base}/lib/systemd/system/multi-user.target.wants" &&
        ln -nsf ../base_provision.service base_provision.service &&
        cd "${working_basedir}"
    fi

  else
    echo "No GitHub repository was specified. Skipping auto-provisioner part."
  fi
}

function main() {
  ## Base checks
  [ -z "$v_sourceimage" ] && {
    echo "Please specify image which has to be modified."
    exit 1
  }
  [ ! -e "$v_sourceimage" ] && { echo "$v_sourceimage could not be found." && exit 1; }
  [ ! -e "$v_sshkey" ] && { echo "$v_sshkey could not be found." && exit 1; }

  if [ -z "$v_targetimage" ]; then
    echo "Target image is empty, all work is done on $v_sourceimage instead."
    v_targetimage=$v_sourceimage
  else
    echo "Creating a copy of $v_sourceimage to $v_targetimage. Work will be done there."
    cp -v $v_sourceimage $v_targetimage
  fi

  boot_fs=""
  root_fs=""

  echo "Finding filesystems in OS image"
  devices=$(get_filesystems $v_targetimage)
  echo "Found filesystems:"
  echo "$devices"
  for device in $devices; do
    echo "Mounting filesystem $device"
    mountpoint=$(mktemp -d -p $working_basedir)
    mount_filesystem "$v_targetimage" "$device" "$mountpoint"

    # Checking where to find which filesystem - optimistically looking for cmdline.txt in BootFS and rpi-update in RootFS
    echo "Checking if we have a root or boot fs here..."
    if [ -e "$mountpoint/cmdline.txt" ]; then
      echo "Found boot filesystem"
      boot_fs=$mountpoint
    elif [ -e "$mountpoint/usr/bin/rpi-update" ]; then
      echo "Found root filesystem"
      root_fs=$mountpoint
    fi
  done

  [ -n "$boot_fs" ] && prepare_bootfs $boot_fs
  [ -n "$root_fs" ] && prepare_rootfs $root_fs

}

check_if_sudo
main

echo "Now run \"sudo ${scripts_basedir}/burnRaspiImage.sh -I $v_targetimage -D [StorageDevice]\" to transfer the image."