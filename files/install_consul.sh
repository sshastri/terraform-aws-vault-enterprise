#!/usr/bin/env bash

readonly CONFIG_PATH="/etc/consul"
readonly INSTALL_PATH="/usr/local/bin"
readonly DATA_PATH="/var/lib/consul"

readonly SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"

readonly DEFAULT_NETWORK_INTERFACE="$(ls -1 /sys/class/net | grep -v lo | sort -r | head -n 1)"
readonly DEFAULT_IP_ADDRESS="$(ip address show $DEFAULT_NETWORK_INTERFACE | awk '{print $2}' | egrep -o '([0-9]+\.){3}[0-9]+')"

readonly INSTANCE_ID="$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
readonly AWS_REGION="$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -c -r .region)"
readonly AWS_AVAILABILITY_ZONE="$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -c -r .availabilityZone)"

source "$SCRIPT_PATH/funcs.sh"

install_consul() {
  local -r func="install_consul"

  create_user consul "$CONFIG_PATH"

  log "INFO" $func "Creating Consul directories..."
  mkdir "$CONFIG_PATH" "$CONFIG_PATH/certs" "$DATA_PATH"
  chmod 0750 "$CONFIG_PATH" "$CONFIG_PATH/certs" "$DATA_PATH"
  chown consul:consul "$CONFIG_PATH" "$CONFIG_PATH/certs" "$DATA_PATH"

  log "INFO" $func "Unpacking Consul..."
  cd "$INSTALL_PATH" && unzip -qu "$SCRIPT_PATH/consul.zip"
  chown consul:consul consul
  chmod 0755 consul

  log "INFO" $func "Creating Consul service..."
  cat > /etc/systemd/system/consul.service <<EOF
[Unit]
Description="HashiCorp Consul - A service mesh solution"
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=$CONFIG_PATH/config.hcl

[Service]
User=${username}
Group=${username}
ExecStart=$INSTALL_PATH/consul agent -config-file $CONFIG_PATH/config.hcl
ExecReload=$INSTALL_PATH/consul reload
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
}

configure_consul() {
  local -r func="configure_consul"
  local -r gossip_encryption_key="$(get_ssm_parameter $AWS_REGION $ssm_parameter_gossip_encryption_key)"

  log "INFO" $func "Configuring Consul..."

  cat <<EOF > "$CONFIG_PATH/config.hcl"
datacenter              = "$datacenter"
node_name               = "$INSTANCE_ID"
data_dir                = "$DATA_PATH"
advertise_addr          = "$DEFAULT_IP_ADDRESS"
retry_join              = ["provider=aws addr_type=private_v4 tag_key=$rejoin_tag_key tag_value=$rejoin_tag_value"]
encrypt                 = "$gossip_encryption_key"
encrypt_verify_incoming = true
encrypt_verify_outgoing = true
ca_file                 = "$CONFIG_PATH/certs/ca.pem"
cert_file               = "$CONFIG_PATH/certs/consul.pem"
key_file                = "$CONFIG_PATH/certs/consul.key"
verify_incoming         = true
verify_outgoing         = true
verify_server_hostname  = true

performance = {
  raft_multiplier = 1
}

EOF

  if [[ $server -eq 0 ]]
  then
    log "INFO" $func "Configuring Consul in client mode..."

    cat <<EOF >> "$CONFIG_PATH/config.hcl"
ports = {
  serf_wan = -1
}
EOF
  else
    log "INFO" $func "Configuring Consul in server mode..."
    assert_not_empty "--bootstrap-expect" "$bootstrap_expect"

    cat <<EOF >> "$CONFIG_PATH/config.hcl"
server           = true
bootstrap_expect = $bootstrap_expect

# All services bind to 127.0.0.1 by default
# Set HTTPS to listen on the default network interface
addresses = {
  https = "$DEFAULT_IP_ADDRESS"
}

ports = {
  https    = 8501
  serf_wan = -1
}

autopilot = {
  redundancy_zone_tag = "$AWS_AVAILABILITY_ZONE"
}
EOF
  fi

  chmod 0640 "$CONFIG_PATH/config.hcl"
  chown consul:consul "$CONFIG_PATH/config.hcl"

  log "INFO" $func "Retrieving Consul TLS certificates..."
  assert_not_empty "--ssm-parameter-tls-ca" "$ssm_parameter_tls_ca"
  assert_not_empty "--ssm-parameter-tls-cert" "$ssm_parameter_tls_cert"
  assert_not_empty "--ssm-parameter-tls-key" "$ssm_parameter_tls_key"

  if [ ! -f "$CONFIG_PATH/certs/ca.pem" ]
  then
    get_ssm_parameter $AWS_REGION $ssm_parameter_tls_ca | base64 -d > "$CONFIG_PATH/certs/ca.pem"
    chown consul:consul "$CONFIG_PATH/certs/ca.pem"
    chmod 0640 "$CONFIG_PATH/certs/ca.pem"
    log "INFO" $func "The TLS CA chain file path $CONFIG_PATH/certs/ca.pem has been created..."
  else
    log "INFO" $func "The TLS CA chain file path $CONFIG_PATH/certs/ca.pem already exists. Doing nothing..."
  fi

  if [ ! -f "$CONFIG_PATH/certs/consul.pem" ]
  then
    get_ssm_parameter $AWS_REGION $ssm_parameter_tls_cert | base64 -d > "$CONFIG_PATH/certs/consul.pem"
    chown consul:consul "$CONFIG_PATH/certs/consul.pem"
    chmod 0640 "$CONFIG_PATH/certs/consul.pem"
    log "INFO" $func "The TLS certificate file path $CONFIG_PATH/certs/consul.pem has been created..."
  else
    log "INFO" $func "The TLS certificate file path $CONFIG_PATH/certs/consul.pem already exists. Doing nothing..."
  fi

  if [ ! -f "$CONFIG_PATH/certs/consul.key" ]
  then
    get_ssm_parameter $AWS_REGION $ssm_parameter_tls_key | base64 -d > "$CONFIG_PATH/certs/consul.key"
    chown consul:consul "$CONFIG_PATH/certs/consul.key"
    chmod 0600 "$CONFIG_PATH/certs/consul.key"
    log "INFO" $func "The TLS key file path $CONFIG_PATH/certs/consul.key has been created..."
  else
    log "INFO" $func "The TLS key file path $CONFIG_PATH/certs/consul.key already exists. Doing nothing..."
  fi

  log "INFO" $func "Starting Consul service..."
  systemctl enable consul
  systemctl restart consul
}

install=0
configure=0
datacenter="dc1"
server=0
while [[ $# -gt 0 ]]
do
  key="$1"
  case "$key" in
    --install)
    install=1
    shift
    ;;
    --configure)
    configure=1
    shift
    ;;
    --datacenter)
    datacenter="$2"
    shift 2
    ;;
    --server)
    server=1
    shift
    ;;
    --bootstrap-expect)
    bootstrap_expect="$2"
    shift 2
    ;;
    --rejoin-tag-key)
    rejoin_tag_key="$2"
    shift 2
    ;;
    --rejoin-tag-value)
    rejoin_tag_value="$2"
    shift 2
    ;;
    --ssm-parameter-gossip-encryption-key)
    ssm_parameter_gossip_encryption_key="$2"
    shift 2
    ;;
    --ssm-parameter-tls-ca)
    ssm_parameter_tls_ca="$2"
    shift 2
    ;;
    --ssm-parameter-tls-cert)
    ssm_parameter_tls_cert="$2"
    shift 2
    ;;
    --ssm-parameter-tls-key)
    ssm_parameter_tls_key="$2"
    shift 2
    ;;
    *)
    log "ERROR" $func "Bad argument $key"
    ;;
  esac
done

if [[ ($install -eq 1) && ($configure -eq 1) ]]
then
  install_consul
  configure_consul
elif [[ $install -eq 1 ]]
then
  install_consul
elif [[ $configure -eq 1 ]]
then
  configure_consul
fi