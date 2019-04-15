#!/usr/bin/env bash

readonly CONSUL_USER="consul"
readonly CONSUL_CFG_DIR="/etc/consul"
readonly CONSUL_CERTS_DIR="$CONSUL_CFG_DIR/certs"
readonly CONSUL_INSTALL_DIR="/opt/consul"
readonly CONSUL_BIN_DIR="$CONSUL_INSTALL_DIR/bin"
readonly CONSUL_SCRIPTS_DIR="$CONSUL_INSTALL_DIR/scripts"
readonly CONSUL_VAR_DIR="/var/opt/consul"
readonly CONSUL_DATA_DIR="$CONSUL_VAR_DIR/consul"
readonly TMP_DIR="/tmp/consul"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"

readonly INSTANCE_ID="$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
readonly AWS_REGION="$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -c -r .region)"

function log {
  local -r level="$1"
  local -r func="$2"
  local -r message="$3"
  local -r timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  >&2 echo -e "${timestamp} [${level}] [${SCRIPT_NAME}:${func}] ${message}"
  [ "$level" == "ERROR" ] && exit 1
}

function assert_not_empty {
  local -r func="assert_not_empty"
  local -r arg_name="$1"
  local -r arg_value="$2"

  if [[ -z "$arg_value" ]]; then
    log "ERROR" "$func" "The value for '$arg_name' cannot be empty"
    print_usage
    exit 1
  fi
}

function user_exists {
  local -r func="user_exists"
  local -r username="$CONSUL_USER"
  id "$username" >/dev/null 2>&1
}

function create_user {
  local -r func="create_user"
  local -r username="$CONSUL_USER"
  local -r install_dir="$CONSUL_INSTALL_DIR"

  if $(user_exists "$username"); then
    log "INFO" $func "User $username already exists..."
  else
    log "INFO" $func "Creating user $username..."
    useradd --system --home "$install_dir" --shell /bin/false "$username"
  fi
}

function create_directories {
  local -r func="create_directories"
  local -r username="$CONSUL_USER"
  local -r config_dir="$CONSUL_CFG_DIR"
  local -r certs_dir="$CONSUL_CERTS_DIR"
  local -r config_dir="$CONSUL_CFG_DIR"
  local -r install_dir="$CONSUL_INSTALL_DIR"
  local -r bin_dir="$CONSUL_BIN_DIR"
  local -r var_dir="$CONSUL_VAR_DIR"
  local -r scripts_dir="$CONSUL_SCRIPTS_DIR"
  local -r data_dir="$CONSUL_DATA_DIR"

  log "INFO" $func "Creating Consul directories..."
  for i in "$config_dir" "$certs_dir" "$install_dir" "$bin_dir" "$scripts_dir" "$var_dir" "$data_dir"
  do
    if [ ! -d "$i" ]
    then
      mkdir -p "$i"
      chmod 0750 "$i"
      chown "$username":"$username" "$i"
    fi
  done

  for i in "$install_dir" "$bin_dir" "$scripts_dir"
  do
    if [ ! -d "$i" ]
    then
      mkdir -p "$i"
      chmod 0755 "$i"
      chown "$username":"$username" "$i"
    fi
  done
}

function get_ssm_parameter {
  local -r func="get_ssm_parameter"
  local -r parameter="$1"
  python3 - <<EOP
import boto3

def getParameter(aws_region, param_name):
    """
    This function reads a secure parameter from AWS' SSM service.
    The request must be passed a valid parameter name, as well as
    temporary credentials which can be used to access the parameter.
    The parameter's value is returned.
    """
    # Create the SSM Client
    ssm = boto3.client('ssm',
        region_name=aws_region
    )

    # Get the requested parameter
    response = ssm.get_parameters(
        Names=[
            param_name,
        ],
        WithDecryption=True
    )

    # Store the credentials in a variable
    credentials = response['Parameters'][0]['Value']

    return credentials

if __name__ == "__main__":
    parameter = getParameter("${aws_region}", "${parameter}")
    print(parameter)
EOP
}

function install_consul {
  local -r func="install_consul"
  local -r bin_dir="$CONSUL_BIN_DIR"
  local -r tmp_dir="$TMP_DIR"
  local -r username="$CONSUL_USER"
  local -r config_dir="$CONSUL_CFG_DIR"

  log "INFO" $func "Installing Consul..."
  cd "$bin_dir" && unzip -qu "$tmp_dir/consul.zip"
  chown $username:$username consul
  chmod 0755 consul
  ln -s "$bin_dir/consul" /usr/bin/consul

  cat > /etc/systemd/system/consul.service <<EOF
[Unit]
Description="HashiCorp Consul - A service mesh solution"
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=${config_dir}/config.hcl

[Service]
User=${username}
Group=${username}
ExecStart=${CONSUL_BIN_DIR}/consul agent -config-file ${config_dir}/config.hcl
ExecReload=${CONSUL_BIN_DIR}/consul reload
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
}

function configure_consul {
  local -r func="configure_consul"
  local -r certs_dir="$CONSUL_CERTS_DIR"
  local -r etc_dir="$CONSUL_CFG_DIR"
  local -r username="$CONSUL_USER"
  local -r aws_region="$AWS_REGION"
  local -r net_int=$(ls -1 /sys/class/net | grep -v lo | sort -r | head -n 1)
  local -r ip_addr=$(ip address show $net_int | awk '{print $2}' | egrep -o '([0-9]+\.){3}[0-9]+')
  local -r encrypt_key="$(get_ssm_parameter ${ssm_encrypt_key})"

  log "INFO" $func "Configuring consul..."
  log "INFO" $func "Creating Consul configuration file..."

  cat <<EOF > "$etc_dir/config.hcl"
# ${etc_dir}/config.hcl
datacenter              = "${datacenter}"
node_name               = "${INSTANCE_ID}"
data_dir                = "${CONSUL_DATA_DIR}/data"
ui                      = ${ui}
advertise_addr          = "${ip_addr}"
server                  = ${server}
bootstrap_expect        = ${bootstrap_expect}
retry_join              = ["provider=aws tag_key=${tag_key} tag_value=${tag_value}"]
encrypt                 = "${encrypt_key}"
encrypt_verify_incoming = true
encrypt_verify_outgoing = true
verify_incoming         = false
verify_outgoing         = true
verify_server_hostname  = ${verify_server_hostname}

performance {
  raft_multiplier = 1
}
EOF

  [[ $tls -eq 1 ]] && configure_tls
  chmod 0640 "$etc_dir/config.hcl"
  chown $username:$username "$etc_dir/config.hcl"

  systemctl enable consul
  systemctl restart consul
}

function configure_tls {
  local -r func="configure_tls"
  local -r username="$CONSUL_USER"
  local -r etc_dir="$CONSUL_CFG_DIR"

  log "INFO" $func "Configuring Consul TLS..."
  assert_not_empty "-ssm-tls-ca" "$ssm_tls_ca"
  assert_not_empty "-ssm-tls-cert" "$ssm_tls_cert"
  assert_not_empty "-ssm-tls-key" "$ssm_tls_key"

  if [ ! -f "$certs_dir/ca.pem" ]
  then
    get_ssm_parameter ${ssm_tls_ca} | base64 -d > "$certs_dir/ca.pem"
    chown $username:$username "$certs_dir/ca.pem"
    chmod 0640 "$certs_dir/ca.pem"
    log "INFO" $func "The TLS CA chain file path $certs_dir/ca.pem has been created..."
  else
    log "INFO" $func "The TLS CA chain file path $certs_dir/ca.pem already exists. Doing nothing..."
  fi

  if [ ! -f "$certs_dir/consul.pem" ]
  then
    get_ssm_parameter ${ssm_tls_cert} | base64 -d > "$certs_dir/consul.pem"
    chown $username:$username "$certs_dir/consul.pem"
    chmod 0640 "$certs_dir/consul.pem"
    log "INFO" $func "The TLS cert file path $certs_dir/consul.pem has been created..."
  else
    log "INFO" $func "The TLS cert file path $certs_dir/consul.pem already exists. Doing nothing..."
  fi

  if [ ! -f "$certs_dir/consul.key" ]
  then
    get_ssm_parameter ${ssm_tls_key} | base64 -d > "$certs_dir/consul.key"
    chown $username:$username "$certs_dir/consul.key"
    chmod 0600 "$certs_dir/consul.key"
    log "INFO" $func "The TLS key file path $certs_dir/consul.key has been created..."
  else
    log "INFO" $func "The TLS cert file path $certs_dir/consul.key already exists. Doing nothing..."
  fi

  log "INFO" $func "Updating Consul configuration file..."
  cat <<EOF >> "$etc_dir/config.hcl"

ca_file   = "${certs_dir}/ca.pem"
cert_file = "${certs_dir}/consul.pem"
key_file  = "${certs_dir}/consul.key"

# All services bind to 127.0.0.1 by default
# Set HTTPS to listen on the default network interface
addresses {
  https = "${ip_addr}"
}
EOF
}

install=0
config=0
server="false"
verify_server_hostname="false"
ui="false"
tls=0
bootstrap="0"
datacenter="dc1"
while [[ $# -gt 0 ]]
do
  key="$1"
  case "$key" in
    -install)
    install=1
    shift
    ;;
    -configure)
    config=1
    shift
    ;;
    -server)
    server="true"
    shift
    ;;
    -verify-server-hostname)
    verify_server_hostname="true"
    shift
    ;;
    -ui)
    ui="true"
    shift
    ;;
    -enable-tls)
    tls=1
    shift
    ;;
    -tag-key)
    tag_key="$2"
    shift 2
    ;;
    -tag-value)
    tag_value="$2"
    shift 2
    ;;
    -ssm-encrypt-key)
    ssm_encrypt_key="$2"
    shift 2
    ;;
    -ssm-tls-ca)
    ssm_tls_ca="$2"
    shift 2
    ;;
    -ssm-tls-cert)
    ssm_tls_cert="$2"
    shift 2
    ;;
    -ssm-tls-key)
    ssm_tls_key="$2"
    shift 2
    ;;
    -bootstrap-expect)
    bootstrap_expect="$2"
    shift 2
    ;;
    -datacenter)
    datacenter="$2"
    shift 2
    ;;
    *)
    log "ERROR" $func "Bad argument $key"
    ;;
  esac
done

if [[ ($install -eq 1) && ($config -eq 1) ]]
then
  create_user
  create_directories
  install_consul
  configure_consul
elif [[ $install -eq 1 ]]
then
  create_user
  create_directories
  install_consul
elif [[ $config -eq 1 ]]
then
  configure_consul
fi