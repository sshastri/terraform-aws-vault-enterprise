#!/usr/bin/env bash

export PATH="/usr/local/bin:$PATH"

TMP_PATH="/tmp/consul"

# Set umask to set correct permissions in case the system is well hardened
umask 022

function log {
  local -r level="$1"
  local -r func="$2"
  local -r message="$3"
  local -r timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  >&2 echo -e "$${timestamp} [$${level}] [$${func}] $${message}"
  [ "$level" == "ERROR" ] && exit 1
}

function install_dependencies {
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
      DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip python3-jinja2 unzip jq awscli
      pip3 install boto3
      ;;
    yum)
      yum install -y epel-release
      yum install -y python36-pip python36-jinja2 unzip jq awscli
      pip3 install boto3
      ;;
    yum_amzn2)
      yum install -y python3-pip unzip jq awscli
      pip3 install jinja2 boto3
      ;;
  esac
}

function copy_artifacts {
  local -r func="copy_artifacts"

  if [ ! -d $TMP_PATH ]
  then
    mkdir $TMP_PATH
  fi
  log "INFO" "$func" "Copying consul install script from S3..."
  aws s3 cp "s3://${s3_bucket}/${s3_path}/install_consul.sh" "$TMP_PATH/install.sh"
  chmod 0755 "$TMP_PATH/install.sh"

  log "INFO" "$func" "Copying consul binary from S3..."
  aws s3 cp "s3://${s3_bucket}/${s3_path}/${consul_zip}" "$TMP_PATH/consul.zip"
}


opts="-server -bootstrap-expect ${bootstrap_count} -datacenter vault -tag-key ${tag_key} -tag-value ${tag_value} -enable-tls -ssm-encrypt-key ${ssm_encrypt_key} -ssm-tls-ca ${ssm_tls_ca} -ssm-tls-cert ${ssm_tls_cert} -ssm-tls-key ${ssm_tls_key}"
if [ ${packerized} == 0 ]
then
  install_dependencies
  copy_artifacts
  "$TMP_PATH/install.sh" -install -configure $opts
else
  /opt/consul/scripts/install.sh -configure $opts
fi
