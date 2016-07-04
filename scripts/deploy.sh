#!/bin/bash
function usage()
 {
    echo "INFO:"
    echo "Usage: deploy.sh [storage-account-name] [storage-account-key] [ansible user]"
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

function install_ansible()
{
    log "Install software-properties-common ..."
    until apt-get --yes install software-properties-common
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
   
    log "Install git ..."
    until apt-get --yes install git
    do
      log "Lock detected on apt-get while install Try again..."
      sleep 2
    done

    log "Install unzip ..."
    until apt-get --yes install unzip
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


function generate_sshkeys()
{
  echo -e 'y\n'|ssh-keygen -b 4096 -f id_rsa -t rsa -q -N ''
}

function put_sshkeys()
 {
   
    log "Install azure storage python module ..."
    pip install azure-storage

    # Push both Private and Public Key
    log "Push ssh keys to Azure Storage"
    python WriteSSHToPrivateStorage.py "${STORAGE_ACCOUNT_NAME}" "${STORAGE_ACCOUNT_KEY}" id_rsa
    error_log "Unable to write id_rsa to storage account ${STORAGE_ACCOUNT_NAME}"
    python WriteSSHToPrivateStorage.py "${STORAGE_ACCOUNT_NAME}" "${STORAGE_ACCOUNT_KEY}" id_rsa.pub
    error_log "Unable to write id_rsa.pub to storage account ${STORAGE_ACCOUNT_NAME}"

}

function fix_etc_hosts()
{
  log "Add hostame and ip in hosts file ..."
  IP=$(ip addr show eth0 | grep inet | grep -v inet6 | awk '{ print $2; }' | sed 's?/.*$??')
  HOST=$(hostname)
  echo "${IP}" "${HOST}" >> /etc/hosts
}

function configure_ansible()
{
  log "Generate ansible files..."
  rm -rf /etc/ansible
  error_log "Unable to remove /etc/ansible directory"
  mkdir -p /etc/ansible
  error_log "Unable to create /etc/ansible directory"
  
  # Remove Deprecation warning
  printf "[defaults]\ndeprecation_warnings = False\nhost_key_checking = False\n\n"    >>  "${ANSIBLE_CONFIG_FILE}"
  
  # Shorten the ControlPath to avoid errors with long host names , long user names or deeply nested home directories
  echo  $'[ssh_connection]\ncontrol_path = ~/.ssh/ansible-%%h-%%r'                    >> "${ANSIBLE_CONFIG_FILE}"   
  # fix ansible bug
  printf "\npipelining = True\n"                                                      >> "${ANSIBLE_CONFIG_FILE}"   
  
  let nWeb=${numberOfFront}-1
  let nBck=${numberOfBack}-1
  # Generate Hostfile for Front and Back
  # All Nodes
  
  nWebPad=$(printf "%06d" "${nWeb}")  

  echo "[cluster]"                                                                                                                         >>  "${ANSIBLE_HOST_FILE}"
  for i in $(seq 0 $nWeb)
  do
    suffix=$(printf "%06d" "${i}")
    echo "${frVmName}${suffix} ansible_user=${ANSIBLE_USER} ansible_ssh_private_key_file=/home/${ANSIBLE_USER}/.ssh/id_rsa"                >> "${ANSIBLE_HOST_FILE}"
  done

  echo "${bkVmName}[0:$nBck] ansible_user=${ANSIBLE_USER} ansible_ssh_private_key_file=/home/${ANSIBLE_USER}/.ssh/id_rsa"                  >> "${ANSIBLE_HOST_FILE}"
  echo "[front]"                                                                                                                           >> "${ANSIBLE_HOST_FILE}"

  for i in $(seq 0 $nWeb)
  do
    suffix=$(printf "%06d" "${i}")
    echo "${frVmName}${suffix} ansible_user=${ANSIBLE_USER} ansible_ssh_private_key_file=/home/${ANSIBLE_USER}/.ssh/id_rsa"                >> "${ANSIBLE_HOST_FILE}"
  done
  

  echo "[back]"                                                                                                                            >> "${ANSIBLE_HOST_FILE}"
  echo "${bkVmName}0 ansible_user=${ANSIBLE_USER} ansible_ssh_private_key_file=/home/${ANSIBLE_USER}/.ssh/id_rsa"        >> "${ANSIBLE_HOST_FILE}"
  if [ "${numberOfBack}" -gt 2 ]; then
  echo "${bkVmName}[1:$nBck] mysql_role=slave ansible_user=${ANSIBLE_USER} ansible_ssh_private_key_file=/home/${ANSIBLE_USER}/.ssh/id_rsa" >> "${ANSIBLE_HOST_FILE}"
  else
  echo "${bkVmName}1 ansible_user=${ANSIBLE_USER} ansible_ssh_private_key_file=/home/${ANSIBLE_USER}/.ssh/id_rsa"         >> "${ANSIBLE_HOST_FILE}" 
  fi
  
  echo "[master]"                                                                                                                          >> "${ANSIBLE_HOST_FILE}"
  echo "${bkVmName}0"                                                                                                                      >> "${ANSIBLE_HOST_FILE}"
  echo "[slave]"                                                                                                                           >> "${ANSIBLE_HOST_FILE}"
  if [ "${numberOfBack}" -gt 2 ]; then
  echo "${bkVmName}[1:$nBck]"                                                                                                              >> "${ANSIBLE_HOST_FILE}"
  else
  echo "${bkVmName}1"                                                                                                                      >> "${ANSIBLE_HOST_FILE}" 
  fi
  
}

function add_hosts()
{
  let nWeb=${numberOfFront}-1
  let nBck=${numberOfBack}-1
  # Generate Hostfile for Front and Back
  # All Nodes
  echo "### Check${hcSubnetRoot}.4    ${hcVmName}" >> "${HOST_FILE}"
  
  echo "#FRONT#"                                   >> "${HOST_FILE}"
  for i in $(seq 0 $nWeb)
  do
    let j=4+$i
    suffix=$(printf "%06d" "${i}")
    echo "${frSubnetRoot}.${j}    ${frVmName}${suffix}" >> "${HOST_FILE}"
  done
  echo "#/FRONT#"                                 >> "${HOST_FILE}"
  
  echo "#BACK#"                                    >> "${HOST_FILE}"
  for i in $(seq 0 $nBck)
  do
    let j=4+$i
    echo "${bkSubnetRoot}.${j}    ${bkVmName}${i}" >> "${HOST_FILE}"
  done
  echo "#/BACK#"                                   >> "${HOST_FILE}"
}

function get_roles()
{
  ansible-galaxy install -f -r install_roles.yml
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
  mv master.yml group_vars/master.yml
  error_log "Fail to move master vars file to directory group_vars"
  mv slave.yml group_vars/slave.yml
  error_log "Fail to move slaves vars file to directory group_vars"
  mv mysql_default.yml vars/mysql_default.yml
  error_log "Fail to move mysql default vars file to directory vars"
  
}

function create_extra_vars()
{
  d="$(date -u +%Y%m%d%H%M%SZ)"  
  printf "{\n  \"ansistrano_release_version\": \"%s\",\n" "${d}"            > "${EXTRA_VARS}"
  printf "  \"prestashop_lb_name\": \"%s\",\n" "${lbName}"                 >> "${EXTRA_VARS}"
  printf "  \"gabarit\": \"%s\",\n" "${gabarit}"                           >> "${EXTRA_VARS}"
  printf "  \"prestashop_firstname\": \"%s\",\n" "${prestashop_firstname}" >> "${EXTRA_VARS}"
  printf "  \"prestashop_lastname\": \"%s\",\n" "${prestashop_lastname}"   >> "${EXTRA_VARS}"
  printf "  \"prestashop_email\": \"%s\",\n" "${prestashop_email}"         >> "${EXTRA_VARS}"
  printf "  \"prestashop_password\": \"%s\"\n}" "${prestashop_password}"   >> "${EXTRA_VARS}"
}

function deploy_database_cluster()
{
  ansible-playbook deploy-prestashop.yml --extra-vars "@${EXTRA_VARS}" > /tmp/ansible-cluster.log 2>&1
  error_log "Fail to deploy front cluster !"
}

function deploy_code()
{
  ansible-playbook deploy.yml --connection=local -i "localhost," --extra-vars "@${EXTRA_VARS}" > /tmp/ansible-local.log 2>&1
  error_log "Fail to deploy NFS and prestashop code !"
}

log "Execution of Install Script from CustomScript ..."

## Variables

CWD="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"

log "CustomScript Directory is ${CWD}"

BASH_SCRIPT="${0}"
STORAGE_ACCOUNT_NAME="${1}"
STORAGE_ACCOUNT_KEY="${2}"
ANSIBLE_USER="${3}"

hcSubnetRoot="${4}"
frSubnetRoot="${5}"
bkSubnetRoot="${6}"

numberOfFront="${7}"
numberOfBack="${8}"

hcVmName="${9}"
# to match scaleset autonaming
frVmName="${10}"
bkVmName="${11}"
prestashop_password="${12:-prestashop}"
lbName="${13}"
prestashop_firstname="${14}"
prestashop_lastname="${15}"
prestashop_email="${16}"
gabarit=$(echo "${17}" | cut -f2 -d_)

case "${gabarit}" in
    ds1|ds2|ds3|ds4|ds11|ds12|ds13|ds14|d15) isok=true;;
    *)             gabarit="ds1";;
esac

HOST_FILE="/etc/hosts"
ANSIBLE_HOST_FILE="/etc/ansible/hosts"
ANSIBLE_CONFIG_FILE="/etc/ansible/ansible.cfg"

EXTRA_VARS="${CWD}/extra_vars.json"

##
fix_etc_hosts
generate_sshkeys
ssh_config
install_ansible
put_sshkeys
add_hosts
configure_ansible
get_roles
configure_deployment
create_extra_vars
deploy_code
deploy_database_cluster


log "Success : End of Execution of Install Script from CustomScript"

exit 0