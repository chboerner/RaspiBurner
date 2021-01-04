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
  # Always define full service name, no wildcards!
  check_service="apt-daily.service apt-daily-upgrade.service"

  # Check if any of the defined services are not in state inactive and wait until all are
  while [ ! $(systemctl list-units --state=inactive ${check_service} | egrep "[^\s]*service\s*" | wc -l) -eq $(echo $check_service | wc -w) ]; do
    echo "Waiting to get APT lock..."
    sleep 2;
  done

  # Only after all services are inactive start installing Ansible
  sudo apt-get install -y ansible
else
  echo "Ansible is installed. Nothing to do."
fi

echo "Running Playbook "${provision_basedir}/${provision_playbook}""
runuser -u ${provision_user} -- ansible-playbook -vv "${provision_basedir}/${provision_playbook}" >> /tmp/provision.$(date +%F_%X) 2>&1
