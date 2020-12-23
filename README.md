# Description
BurnRaspi consists of two main shell scripts:
- prepareRaspiImage prepares a standard RaspberryPi OS image with some settings as described below.
- burnRaspiImage writes the image to a SD card and optionally creates a secondy filesystem.

## prepareRaspiImage.sh
This script is meant to take a standard RaspberryPI OS/Raspbian image as input and run some actions on it.
The script needs to be run with elevated permissions. It is recommended to use sudo to do so. There are two reasons why
this is required. During the process the image is mounted to a loopback device. And some settings require to change
files which belong to the root user inside the image. 

```
Usage sudo prepareRaspiImage.sh <Options>
Image options:
-I <disk image>           Raw OS Image with RasperryPiOS that should be modified.
-T <target image>         This option creates a copy of Raw OS image to work on it. Default is to work on the original.

RaspberryPi settings:
-H <hostname>             Hostname to be configured for this OS image without domain portion
-s <ssh key>              Use this ssh key instead of the configured default ($v_sshkey) for user $v_username

Auto provision options:
-r <GitHub Repository>    GitHub Repository containing the provisioning code
-k <GitHub Deploy Key>    Deployment key to be used for private/protected repositories
-p <Provision base dir>   Directory where the GitHub repository is cloned (default: $v_provision_basedir)
-P <Playbook File>        Ansible playbook file that should be run for initial provisioning
-a                        Enable Ansible Autoprovisioning after boot (default: $v_autoprovision)
                          Requires at least the GitHub repository to be named.
```

### Details on Image options
It is required to define at least the input image (-I).<br>
If no target image is defined all work is automatically done on the input image.

### Details on RaspberryPi settings
The hostname setting is set /etc/hostname and will be used by the RaspberryPi. If you configure your DHCP client
(plus the DHCP and DNS servers) correctly this will be used as the hostname. A sample dhcpcd.conf could look like this:
```
fqdn both
hostname_short

option rapid_commit
option domain_name_servers, domain_name, domain_search, host_name
option ntp_servers
option classless_static_routes
require dhcp_server_identifier
slaac private

release
```

The SSH key defined with -s is used to add the public key to the authorized_key file for the "pi" user. This setting
is (apart from the image) the only mandatory setting but will fall back to ~/.ssh/id_rsa if not specified.

### Details on Auto provision options
The auto provision options take some parameters as described here and configure a script and a SystemD service. If the
-a flag is set these will be run at the boot of the RaspberryPi.
The provisioner script deployed to the image will clone the GitHub repository, install Ansible and then run the playbook
defined. The script is rather generic so it can be used for similar projects. The configuration is stored at
/.provision.conf

The option -r defines the GitHub repository to be cloned.<br>
If your repository is private you need to add a Deploy key to
the repository (read permissions should be sufficient). The key must then be provided with the -k option. This will
store the key in the .ssh folder of user pi and set the ssh configuration to use this key. It also defines "git" as
username to be used, so you can omit this in the repository name.<br>
If your repository is public you may also use the https URLs of the repository.

The provision base dir (-p) options defines where the repository is cloned to. This directory and all content will be 
chowned to user "pi" after cloning. The option "-P" names the playbook that should be run.<br>
The provisioning itself will be run as user pi. If you choose to change this you need to edit either the script
files/base_provision.sh or change the username on top of prepareRaspImage.sh. Make sure this user exists in the image
and has sufficient permissions.

# burnRaspiImage.sh
This script will take a RaspberryPI OS/Raspbian image (-I) and write it to a device (-D).<br>
Hint: this will work also with standard/unmodified images.

The more interesting option of this script is "-S". Here you can define the size of an additional filesystem. This will
be created at the end of the disk. Having this in place the auto-resize function of Raspbian will leave the occupied
space untouched. The main reason I wrote this was to have a separate "data" filesystem. Another reason could be to
restrict the size of the RaspberryPI root filesystem to make it portable to smaller cards.

```
Usage $0 -D <disk device> -H <hostname>

-D <disk device>      Device name with RaspberryPiOS. Only device, not file systems!
                      Ex. /dev/sdd instead of /dev/sdd1
-I <image>            RaspberryPiOS image which should be written to the disk.
-S <size>             Size of secondary partition in Gigabytes (created at end of disk)
```
