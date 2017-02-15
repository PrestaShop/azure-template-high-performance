#!/bin/bash
function usage()
 {
    echo "INFO:"
    echo "Usage: deploy-scaleset.sh [storage-account-name] [storage-account-key] [ansible user]"
}

error_log()
{
    if [ "$?" != "0" ]; then
        log "$1"
        log "Deployment ends with an error" "1"
        exit 1
    fi
}

function log()
{

  mess="$(hostname): $1"
  echo "[LOG] ${BASH_SCRIPT} : ${mess}"
  logger -t "${BASH_SCRIPT}" "${mess}"

}

function ssh_config()
{
  log "Configure ssh..."
  log "Create ssh configuration for ${ANSIBLE_USER}"

  printf "Host *\n  user %s\n  StrictHostKeyChecking no\n" "${ANSIBLE_USER}"  >> "/home/${ANSIBLE_USER}/.ssh/config"

  error_log "Unable to create ssh config file for user ${ANSIBLE_USER}"

  log "Copy generated keys..."

  cp id_rsa "/home/${ANSIBLE_USER}/.ssh/id_rsa"
  error_log "Unable to copy id_rsa key to $ANSIBLE_USER .ssh directory"

  cp id_rsa.pub "/home/${ANSIBLE_USER}/.ssh/id_rsa.pub"
  error_log "Unable to copy id_rsa.pub key to $ANSIBLE_USER .ssh directory"

  cat "/home/${ANSIBLE_USER}/.ssh/id_rsa.pub" >> "/home/${ANSIBLE_USER}/.ssh/authorized_keys"
  error_log "Unable to copy $ANSIBLE_USER id_rsa.pub to authorized_keys "

  chmod 700 "/home/${ANSIBLE_USER}/.ssh"
  error_log "Unable to chmod $ANSIBLE_USER .ssh directory"

  chown -R "${ANSIBLE_USER}:" "/home/${ANSIBLE_USER}/.ssh"
  error_log "Unable to chown to $ANSIBLE_USER .ssh directory"

  chmod 400 "/home/${ANSIBLE_USER}/.ssh/id_rsa"
  error_log "Unable to chmod $ANSIBLE_USER id_rsa file"

  chmod 644 "/home/${ANSIBLE_USER}/.ssh/id_rsa.pub"
  error_log "Unable to chmod $ANSIBLE_USER id_rsa.pub file"

  chmod 400 "/home/${ANSIBLE_USER}/.ssh/authorized_keys"
  error_log "Unable to chmod $ANSIBLE_USER authorized_keys file"

}

function ssh_config_root()
{

  log "Create ssh configuration for root"

  printf "Host *\n  user %s\n  StrictHostKeyChecking no\n" "root"  >> "/root/.ssh/config"

  error_log "Unable to create ssh config file for user root"

  log "Copy generated keys..."

  cp id_rsa "/root/.ssh/id_rsa"
  error_log "Unable to copy id_rsa key to root .ssh directory"

  cp id_rsa.pub "/root/.ssh/id_rsa.pub"
  error_log "Unable to copy id_rsa.pub key to root .ssh directory"

  cat "/root/.ssh/id_rsa.pub" >> "/root/.ssh/authorized_keys"
  error_log "Unable to copy root id_rsa.pub to authorized_keys "

  chmod 700 "/root/.ssh"
  error_log "Unable to chmod root .ssh directory"

  chown -R "root:" "/root/.ssh"
  error_log "Unable to chown to root .ssh directory"

  chmod 400 "/root/.ssh/id_rsa"
  error_log "Unable to chmod root id_rsa file"

  chmod 644 "/root/.ssh/id_rsa.pub"
  error_log "Unable to chmod root id_rsa.pub file"

  chmod 400 "/root/.ssh/authorized_keys"
  error_log "Unable to chmod root authorized_keys file"

}

function install_packages()
{
    log "Install software-properties-common ..."
    until apt-get --yes install software-properties-common build-essential libssl-dev libffi-dev python-dev
    do
      log "Lock detected on apt-get while install Try again..."
      sleep 2
    done

    log "Update System ..."
    until apt-get --yes update
    do
      log "Lock detected on apt-get while install Try again..."
      sleep 2
    done

    log "Install git ..."
    until apt-get --yes install git
    do
      log "Lock detected on apt-get while install Try again..."
      sleep 2
    done

    log "Install pip ..."
    until apt-get --yes install python-pip
    do
      log "Lock detected on apt-get while install Try again..."
      sleep 2
    done
}

function install_ansible()
{
    log "Update System ..."
    until apt-get --yes update
    do
      log "Lock detected on apt-get while install Try again..."
      sleep 2
    done

    log "Install ppa:ansible/ansible ..."
    until apt-add-repository --yes ppa:ansible/ansible
    do
      log "Lock detected on apt-get while install Try again..."
      sleep 2
    done

    log "Update System ..."
    until apt-get --yes update
    do
      log "Lock detected on apt-get while install Try again..."
      sleep 2
    done

    log "Install Ansible ..."
    until apt-get --yes install ansible
    do
      log "Lock detected on apt-get while install Try again..."
      sleep 2
    done

    log "Install sshpass"
    until apt-get --yes install sshpass
    do
      log "Lock detected on apt-get while install Try again..."
      sleep 2
    done
}


function get_sshkeys()
 {

    c=0;
    log "Install azure storage python module ..."
    pip install azure-storage

    # Get both Private and Public Key
    log "Get ssh keys to Azure Storage (id_rsa)"
    until python GetSSHFromPrivateStorage.py "${STORAGE_ACCOUNT_NAME}" "${STORAGE_ACCOUNT_KEY}" id_rsa
    do
        log "Fails to Get id_rsa key trying again ..."
        sleep 60
        let c=${c}+1
        if [ "${c}" -gt 9 ]; then
           log "Timeout to get id_rsa key exiting ..."
           exit 1
        fi
    done

    log "Get ssh keys to Azure Storage (id_rsa.pub)"
    until python GetSSHFromPrivateStorage.py "${STORAGE_ACCOUNT_NAME}" "${STORAGE_ACCOUNT_KEY}" id_rsa.pub
    do
        log "Fails to Get id_rsa.pub key, trying again ..."
        sleep 20
        let c=${c}+1
        if [ "${c}" -gt 9 ]; then
           log "Timeout to get id_rsa.pub key, exiting ..."
           exit 1
        fi
    done
    error_log "Fails to Get id_rsa.pub key"
}

function fix_etc_hosts()
{
  log "Add hostame and ip in hosts file ..."
  IP=$(ip addr show eth0 | grep inet | grep -v inet6 | awk '{ print $2; }' | sed 's?/.*$??')
  HOST=$(hostname)
  echo "${IP}" "${HOST}" >> "${HOST_FILE}"

  echo "${hcSubnetRoot}.4    ${NFSVmName}" >> "${HOST_FILE}"
}


function add_host_entry()
{
  log "Add Host entry front for sync ..."

  let nFront=${numberOfFront}-1

  for i in $(seq 0 $nFront)
  do
    let j=4+$i
    suffix=$(printf "%06d" "${i}")
    echo "${frSubnetRoot}.${j}    ${frVmName}${suffix}" >> "${HOST_FILE}"
    let k=$i+1
  done

}

function add_host_entry_back()
{
 if [ -f "${nfs_mountpoint}/etc/hosts" ]; then
     tag="BACK"
     sed -n "/#$tag#/,/#\/$tag#/p" "${nfs_mountpoint}/etc/hosts" >> "${HOST_FILE}"
  fi

}

function configure_ansible()
{
  log "Generate ansible files..."
  rm -rf /etc/ansible
  error_log "Unable to remove /etc/ansible directory"
  mkdir -p /etc/ansible
  error_log "Unable to create /etc/ansible directory"

  # Remove Deprecation warning
  printf "[defaults]\ndeprecation_warnings = False\nhost_key_checking = False\nexecutable = /bin/bash\n\n"    >>  "${ANSIBLE_CONFIG_FILE}"

  # Shorten the ControlPath to avoid errors with long host names , long user names or deeply nested home directories
  echo  $'[ssh_connection]\ncontrol_path = ~/.ssh/ansible-%%h-%%r'                    >> "${ANSIBLE_CONFIG_FILE}"
  # fix ansible bug
  printf "\npipelining = True\n"                                                      >> "${ANSIBLE_CONFIG_FILE}"

  # Handle SSH failures with retry
  printf "\nretries = 10\n"                                                           >> "${ANSIBLE_CONFIG_FILE}"

  let nWeb=${numberOfFront}-1
  echo "[front]"                                                                                                                     >> "${ANSIBLE_HOST_FILE}"
  for i in $(seq 0 $nWeb)
  do
    suffix=$(printf "%06d" "${i}")
    echo "${frVmName}${suffix} ansible_user=${ANSIBLE_USER} ansible_ssh_private_key_file=/home/${ANSIBLE_USER}/.ssh/id_rsa"          >> "${ANSIBLE_HOST_FILE}"
  done

}

function get_roles()
{
  ansible-galaxy install -f -r install_roles_scaleset.yml
  error_log "Can't get roles from Galaxy'"
}


function configure_deployment()
{
  mkdir -p vars
  error_log "Fail to create vars directory"
  mkdir -p group_vars
  error_log "Fail to create group_vars  directory"
  mv main.yml vars/main.yml
  error_log "Fail to move vars file to directory vars"

}

function create_extra_vars()
{
  d="$(date -u +%Y%m%d%H%M%SZ)"
  HOST=$(hostname)
  printf "{\n  \"ansistrano_release_version\": \"%s\",\n" "${d}"            > "${EXTRA_VARS}"
  printf "  \"nfsserver\": \"%s\",\n" "${NFSVmName}"                       >> "${EXTRA_VARS}"
  printf "  \"current_hostname\": \"%s\",\n" "${HOST}"                     >> "${EXTRA_VARS}"
  printf "  \"prestashop_lb_name\": \"%s\",\n" "${lbName}"                 >> "${EXTRA_VARS}"
  printf "  \"prestashop_firstname\": \"%s\",\n" "${prestashop_firstname}" >> "${EXTRA_VARS}"
  printf "  \"prestashop_lastname\": \"%s\",\n" "${prestashop_lastname}"   >> "${EXTRA_VARS}"
  printf "  \"prestashop_email\": \"%s\",\n" "${prestashop_email}"         >> "${EXTRA_VARS}"
  printf "  \"prestashop_password\": \"%s\"\n}" "${prestashop_password}"   >> "${EXTRA_VARS}"
}

function wait_for_extension()
{
    log "Install htop ..."
    until apt-get --yes install htop
    do
      log "Lock detected on apt-get while install Try again..."
      sleep 2
    done
}

function start_nc()
{
  log "Pause script for Control VM..."
  nohup nc -d -l 3333 >/tmp/nohup.log 2>&1
}

function deploy_nfs_scaleset()
{

  INVENTORY_FILE="${ANSIBLE_HOST_FILE}"

  log "Deploying NFS ScaleSet..."

  ansible-playbook deploy-scaleset-nfs.yml --connection=local -i "${INVENTORY_FILE}" --extra-vars "@${EXTRA_VARS}" > /var/log/ansible-nfs.log 2>&1
  error_log "Fail to deploy NFS scale set node !"
}



function deploy_scaleset()
{

  nfs_mountpoint=$(awk '/nfs_mountpoint:/ { print $2; }' vars/main.yml | tr -d '"')

  if [ -f "${nfs_mountpoint}/etc/ansible/hosts" ]; then
     INVENTORY_FILE="/data/etc/ansible/hosts"
  else
     INVENTORY_FILE="${ANSIBLE_HOST_FILE}"
  fi

  log "Deploying ScaleSet..."

  ansible-playbook deploy-scaleset.yml --connection=local -i "${INVENTORY_FILE}" --extra-vars "@${EXTRA_VARS}" > /var/log/ansible.log 2>&1
  error_log "Fail to deploy scale set node !"
}

function remove_keys()
 {
    # Removes Blob Key
    log "Remove Blob containing private ssh keys"
    python RemovePrivateStorage.py "${STORAGE_ACCOUNT_NAME}" "${STORAGE_ACCOUNT_KEY}" id_rsa
    error_log "Unable to remove container keys storage account ${STORAGE_ACCOUNT_NAME}"
}



log "Execution of Install Script from CustomScript ..."

## Variables

CWD="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"

log "CustomScript Directory is ${CWD}"

BASH_SCRIPT="${0}"
STORAGE_ACCOUNT_NAME="${1}"
STORAGE_ACCOUNT_KEY="${2}"
ANSIBLE_USER="${3}"

numberOfFront="${4}"
frSubnetRoot="${5}"
# to match autonameing scaleset
frVmName="${6}"
lbName="${7}"
prestashop_password="${8:-prestashop}"
prestashop_firstname="${9}"
prestashop_lastname="${10}"
prestashop_email="${11}"
hcSubnetRoot="${12}"

HOST_FILE="/etc/hosts"
ANSIBLE_HOST_FILE="/etc/ansible/hosts"
ANSIBLE_CONFIG_FILE="/etc/ansible/ansible.cfg"
EXTRA_VARS="${CWD}/extra_vars.json"
NFSVmName="nfs-server"

##

fix_etc_hosts
install_packages
install_ansible
get_sshkeys
ssh_config
ssh_config_root
add_host_entry
configure_ansible
get_roles
configure_deployment
create_extra_vars
wait_for_extension
deploy_nfs_scaleset
add_host_entry_back
deploy_scaleset
remove_keys

# Script Wait for the wait_module from ansible playbook
#start_nc

log "Success : End of Execution of Install Script from CustomScript"

exit 0
