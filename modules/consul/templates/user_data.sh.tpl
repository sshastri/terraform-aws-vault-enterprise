#!/usr/bin/env bash

export PATH="/usr/local/bin:$PATH"

TMP_PATH="/tmp/install_files"

# Set umask to set correct permissions in case the system is well hardened
umask 022

log() {
  local -r level="$1"
  local -r func="$2"
  local -r message="$3"
  local -r timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  >&2 echo -e "$${timestamp} [$${level}] [$${func}] $${message}"
  [ "$level" == "ERROR" ] && exit 1
}

install_dependencies() {
  local -r func="install_dependencies"

  # Check package manager type
  if [ -x "/usr/bin/yum" ]
  then
    uname -r | grep -q amzn2
    if [ $? -eq 0 ]
    then
      local -r pkg_mgr="yum_amzn2"
    else
      local -r pkg_mgr="yum"
    fi
  elif [ -x "/usr/bin/apt-get" ]
  then
    local -r pkg_mgr="apt"
  else
    log "ERROR" $func "This is no good. It looks like there are no supported package managers installed."
  fi

  log "INFO" $func "Installing dependencies..."
  case "$pkg_mgr" in
    apt)
      DEBIAN_FRONTEND=noninteractive apt-get update -y
      DEBIAN_FRONTEND=noninteractive apt-get install -y unzip jq awscli
      ;;
    yum)
      yum install -y epel-release
      yum install -y unzip jq awscli
      ;;
    yum_amzn2)
      yum install -y unzip jq awscli
      ;;
  esac
}

copy_artifacts() {
  local -r func="copy_artifacts"

  if [ ! -d "$TMP_PATH" ]
  then
    mkdir $TMP_PATH
  fi
  log "INFO" "$func" "Copying scripts from S3..."
  aws s3 cp "s3://${s3_bucket}/${s3_path}/install_consul.sh" "$TMP_PATH/install.sh"
  chmod 0755 "$TMP_PATH/install.sh"

  aws s3 cp "s3://${s3_bucket}/${s3_path}/funcs.sh" "$TMP_PATH/funcs.sh"
  chmod 0755 "$TMP_PATH/funcs.sh"

  log "INFO" "$func" "Copying consul binary from S3..."
  aws s3 cp "s3://${s3_bucket}/${s3_path}/${consul_zip}" "$TMP_PATH/consul.zip"
}


opts="--server --bootstrap-expect ${bootstrap_expect} --rejoin-tag-key ${rejoin_tag_key} --rejoin-tag-value ${rejoin_tag_value} --ssm-parameter-gossip-encryption-key ${ssm_parameter_gossip_encryption_key} --ssm-parameter-tls-ca ${ssm_parameter_tls_ca} --ssm-parameter-tls-cert ${ssm_parameter_tls_cert} --ssm-parameter-tls-key ${ssm_parameter_tls_key}"

if [ ${packerized} -eq 0 ]
then
  install_dependencies
  copy_artifacts
  "$TMP_PATH/install.sh" --install --configure $opts
else
  /opt/consul/scripts/install.sh --configure $opts
fi

# ${install_script_hash}