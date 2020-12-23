#!/usr/bin/env bash
set -e

source /.provision.conf

echo "Cloning Git repository $github_repo to $provision_basedir"
git clone --branch master "${github_repo}" "${provision_basedir}"
echo "Adjusting permissions of clone"
provision_group=$(getent group $(id -g ${provision_user}) | cut -d ':' -f 1)
chown -R ${provision_user}:${provision_group} "${provision_basedir}"

echo "Checking if Ansible is installed"
if [ $(which ansible-playbook | wc -l) -eq 0 ]; then
  echo "Installing Ansible"
  sudo apt install -y ansible
else
  echo "Nothing to do. Ansible was found."
fi

echo "Running Playbook "${provision_basedir}/${provision_playbook}""
runuser -u ${provision_user} -c ansible-playbook "${provision_basedir}/${provision_playbook}"