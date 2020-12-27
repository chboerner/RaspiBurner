#!/usr/bin/env bash
set -e

source /.provision.conf

if [ ! -e "${provision_basedir}/.git" ]; then
  echo "Cloning Git repository $github_repo to $provision_basedir"
  mkdir -p "${provision_basedir}"
  provision_group=$(getent group $(id -g ${provision_user}) | cut -d ':' -f 1)
  chown -R ${provision_user}:${provision_group} "${provision_basedir}"
  runuser -u ${provision_user} -- git clone --branch master "${github_repo}" "${provision_basedir}"
else
  cd "${provision_basedir}" && runuser -u ${provision_user} -- git pull
fi

echo "Checking if Ansible is installed"
if [ $(which ansible-playbook | wc -l) -eq 0 ]; then
  echo "Installing Ansible"

  # wait until `apt-get updated` is done to prevent race condition with apt-daily.service
  while ! (systemctl list-units --all apt-daily.service | egrep -q '(dead|failed)')
  do
    echo "Waiting to get APT lock..."
    sleep 1;
  done
  sudo apt install -y ansible
else
  echo "Nothing to do. Ansible was found."
fi

echo "Running Playbook "${provision_basedir}/${provision_playbook}""
runuser -u ${provision_user} -- ansible-playbook "${provision_basedir}/${provision_playbook}" >> /tmp/provision.$(date +%F_%X) 2>&1
