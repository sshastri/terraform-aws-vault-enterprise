#!/bin/bash

function log {
  local -r level="$1"
  local -r func="$2"
  local -r message="$3"
  local -r timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  >&2 echo -e "$${timestamp} [$${level}] [$${func}] $${message}"
}

function has_yum {
  [ -n "$(command -v yum)" ]
}

function has_apt_get {
  [ -n "$(command -v apt-get)" ]
}

function is_amzn2 {
  grep -q amzn2 /etc/image-id 2>&1 > /dev/null
  [ $? -eq 0 ]
}

function install_dependencies {
  local -r func="install_dependencies"
  log "INFO" $func "Installing dependencies"

  if $(has_apt_get); then
    DEBIAN_FRONTEND=noninteractive apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip unzip jq curl
    pip3 install awscli
  elif $(has_yum); then
    if $(is_amzn2); then
      yum install -y python3-pip
    else
      yum install -y epel-release
      yum install -y python3-pip unzip jq
    fi
    pip3 install awscli boto3
  else
    log "ERROR" $func "Could not find apt-get or yum. Cannot install dependencies on this OS."
    exit 1
  fi

  log "INFO" "$func" "Creating install dir /tmp/install_files"
  mkdir /tmp/install_files
}

function install_consul {
  local -r func="install_consul"
  local -r install_opts="--consul-bin ${consul_bin} --install-bucket ${install_bucket} --client 1 --tls-ca ${tls_ca} --tag-key ${cluster_tag_key} --tag-value ${cluster_tag_value} --cluster-size ${consul_cluster_size} --ssm-param ${ssm_param}"

  log "INFO" "$func" "copying consul install script"
  aws s3 cp "s3://${install_bucket}/install_files/install-consul.sh" /tmp/install_files

  log "INFO" "$func" "copying get_ssm_param.py script"
  aws s3 cp "s3://${install_bucket}/install_files/get_ssm_param.py" /tmp/install_files

  log "INFO" "$func" "installing consul from binary"
  bash /tmp/install_files/install-consul.sh $${install_opts}
}

function install_vault {
  local -r func="install_vault"
  local install_opts="--vault-bin ${vault_bin} --install-bucket ${install_bucket} --tls-key ${tls_key} --tls-cert ${tls_cert} --api_addr ${api_addr}"

  log "INFO" "$func" "copying vault install script"
  aws s3 cp "s3://${install_bucket}/install_files/install-vault.sh" /tmp/install_files

  log "INFO" "$func" "installing vault from binary"
  echo "USE AUTOUNSEAL = ${use_auto_unseal}"
  if [ ${use_auto_unseal} -eq 1 ]
  then
    install_opts="$${install_opts} --kms-key-arn ${kms_key_arn} --aws-region ${aws_region}"
  fi
  bash /tmp/install_files/install-vault.sh $${install_opts}
}

echo "USE USERDATA = ${use_userdata}"
if [ ${use_userdata} -eq 1 ]
then
  install_dependencies
  install_consul
  install_vault
else
  exit
fi
