#!/usr/bin/env bash

readonly CONSUL_CONFIG_PATH="/etc/consul"
readonly CONSUL_INSTALL_PATH="/usr/local/bin"
readonly CONSUL_DATA_PATH="/var/lib/consul"

readonly VAULT_CONFIG_PATH="/etc/vault"
readonly VAULT_INSTALL_PATH="/usr/local/bin"

readonly TMP_PATH="/tmp/vault"
readonly SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"

readonly DEFAULT_NETWORK_INTERFACE="$(ls -1 /sys/class/net | grep -v lo | sort -r | head -n 1)"
readonly DEFAULT_IP_ADDRESS="$(ip address show $DEFAULT_NETWORK_INTERFACE | awk '{print $2}' | egrep -o '([0-9]+\.){3}[0-9]+')"

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
  local -r user="$1"
  id "$user" >/dev/null 2>&1
}

function create_users {
  local -r func="create_user"
  local -r user="$1"
  local -r home="$2"

  if $(user_exists "$user"); then
    log "INFO" $func "User $user already exists..."
  else
    log "INFO" $func "Creating user $user..."
    useradd --system --home "$home" --shell /bin/false "$user"
  fi
}

function get_ssm_parameter {
  local -r func="get_ssm_parameter"
  local -r parameter="$1"
  
  log "INFO" $func "Retrieving SSM parameter $parameter..."
  aws --region "$AWS_REGION" ssm get-parameter --name "$parameter" --with-description | jq --raw-output '.Parameter.Value'
}

function install_consul {
  local -r func="install_consul"

  create_user consul $CONSUL_CONFIG_PATH

  log "INFO" $func "Creating Consul directories..."
  mkdir "$CONSUL_CONFIG_PATH" "$CONSUL_CONFIG_PATH/certs" "$CONSUL_DATA_PATH"
  chmod 0750 "$CONSUL_CONFIG_PATH" "$CONSUL_CONFIG_PATH/certs" "$CONSUL_DATA_PATH"
  chown consul:consul "$CONSUL_CONFIG_PATH" "$CONSUL_CONFIG_PATH/certs" "$CONSUL_DATA_PATH"

  log "INFO" $func "Unpacking Consul..."
  cd "$CONSUL_INSTALL_PATH" && unzip -qu "$TMP_PATH/consul.zip"
  chown consul:consul consul
  chmod 0755 consul

  log "INFO" $func "Creating Consul service..."
  cat > /etc/systemd/system/consul.service <<EOF
[Unit]
Description="HashiCorp Consul - A service mesh solution"
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=$CONSUL_CONFIG_PATH/config.hcl

[Service]
User=${username}
Group=${username}
ExecStart=$CONSUL_INSTALL_PATH/consul agent -config-file $CONSUL_CONFIG_PATH/config.hcl
ExecReload=$CONSUL_INSTALL_PATH/consul reload
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
}

function install_vault {
  local -r func="install_vault"

  create_user vault $VAULT_CONFIG_PATH

  log "INFO" $func "Creating Vault directories..."
  for i in "$VAULT_CONFIG_PATH" "$VAULT_CONFIG_PATH/certs"
  do
    if [ ! -d "$i" ]
    then
      mkdir "$i"
      chmod 0750 "$i"
      chown vault:vault "$i"
    fi
  done

  log "INFO" $func "Unpacking Vault..."
  cd "$VAULT_INSTALL_PATH" && unzip -qu "$TMP_PATH/vault.zip"
  chown $VAULT_USER:$VAULT_USER vault
  chmod 0755 vault
  setcap cap_ipc_lock=+ep vault

  log "INFO" $func "Creating Vault service..."
  cat > /etc/systemd/system/vault.service <<EOF
[Unit]
Description="HashiCorp Vault - A tool for managing secrets"
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=$VAULT_CONFIG_PATH/config.hcl

[Service]
User=${username}
Group=${username}
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=$VAULT_INSTALL_PATH/vault server -config $$VAULT_CONFIG_PATH/config.hcl
ExecReload=/bin/kill --signal HUP \$MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitInterval=60
StartLimitBurst=3
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
}

function configure_consul {
  local -r func="configure_consul"
  local -r consul_gossip_encryption_key="$(get_ssm_parameter $ssm_parameter_consul_gossip_encryption_key)"

  if [[ $consul_server -eq 0 ]]
  then
    log "INFO" $func "Configuring Consul in client mode..."

    cat <<EOF > "$CONSUL_CONFIG_PATH/config.hcl"
datacenter              = "$consul_datacenter"
node_name               = "$INSTANCE_ID"
data_dir                = "$CONSUL_DATA_PATH"
advertise_addr          = "$DEFAULT_IP_ADDRESS"
retry_join              = ["provider=aws addr_type=private_v4 tag_key=$consul_rejoin_tag_key tag_value=$consul_rejoin_tag_value"]
encrypt                 = "$consul_gossip_encryption_key"
encrypt_verify_incoming = true
encrypt_verify_outgoing = true
ca_file                 = "$CONSUL_CONFIG_PATH/certs/ca.pem"
cert_file               = "$CONSUL_CONFIG_PATH/certs/consul.pem"
key_file                = "$CONSUL_CONFIG_PATH/certs/consul.key"
verify_incoming         = true
verify_outgoing         = true
verify_server_hostname  = true

performance = {
  raft_multiplier  = 1
}

ports = {
  serf_wan = -1
}
EOF
  else
    log "INFO" $func "Configuring Consul in server mode..."
    assert_not_empty "--consul-bootstrap-expect" "$consul_bootstrap_expect"

    cat <<EOF > "$CONSUL_CONFIG_PATH/config.hcl"
datacenter              = "$consul_datacenter"
node_name               = "$INSTANCE_ID"
data_dir                = "$CONSUL_DATA_PATH"
advertise_addr          = "$DEFAULT_IP_ADDRESS"
server                  = true
bootstrap_expect        = $consul_bootstrap_expect
retry_join              = ["provider=aws addr_type=private_v4 tag_key=$consul_rejoin_tag_key tag_value=$consul_rejoin_tag_value"]
encrypt                 = "$consul_gossip_encryption_key"
encrypt_verify_incoming = true
encrypt_verify_outgoing = true
ca_file                 = "$CONSUL_CONFIG_PATH/certs/ca.pem"
cert_file               = "$CONSUL_CONFIG_PATH/certs/consul.pem"
key_file                = "$CONSUL_CONFIG_PATH/certs/consul.key"
verify_incoming         = true
verify_outgoing         = true
verify_server_hostname  = true

performance = {
  raft_multiplier  = 1
}

# All services bind to 127.0.0.1 by default
# Set HTTPS to listen on the default network interface
addresses = {
  https = "$DEFAULT_IP_ADDRESS"
}

ports = {
  https = 8501
  serf_wan = -1
}
EOF
  fi

  chmod 0640 "$CONSUL_CONFIG_PATH/config.hcl"
  chown consul:consul "$CONSUL_CONFIG_PATH/config.hcl"

  log "INFO" $func "Retrieving Consul TLS certificates..."
  assert_not_empty "--ssm-parameter-consul-tls-ca" "$ssm_parameter_consul_tls_ca"
  assert_not_empty "--ssm-parameter-consul-tls-cert" "$ssm_parameter_consul_tls_cert"
  assert_not_empty "--ssm-parameter-consul-tls-key" "$ssm_parameter_consul_tls_key"

  if [ ! -f "$CONSUL_CONFIG_PATH/certs/ca.pem" ]
  then
    get_ssm_parameter $ssm_parameter_consul_tls_ca | base64 -d > "$CONSUL_CONFIG_PATH/certs/ca.pem"
    chown consul:consul "$CONSUL_CONFIG_PATH/certs/ca.pem"
    chmod 0640 "$CONSUL_CONFIG_PATH/certs/ca.pem"
    log "INFO" $func "The TLS CA chain file path $CONSUL_CONFIG_PATH/certs/ca.pem has been created..."
  else
    log "INFO" $func "The TLS CA chain file path $CONSUL_CONFIG_PATH/certs/ca.pem already exists. Doing nothing..."
  fi

  if [ ! -f "$CONSUL_CONFIG_PATH/certs/vault.pem" ]
  then
    get_ssm_parameter $ssm_parameter_consul_tls_cert | base64 -d > "$CONSUL_CONFIG_PATH/certs/consul.pem"
    chown consul:consul "$CONSUL_CONFIG_PATH/certs/consul.pem"
    chmod 0640 "$CONSUL_CONFIG_PATH/certs/consul.pem"
    log "INFO" $func "The TLS certificate file path $CONSUL_CONFIG_PATH/certs/consul.pem has been created..."
  else
    log "INFO" $func "The TLS certificate file path $CONSUL_CONFIG_PATH/certs/consul.pem already exists. Doing nothing..."
  fi

  if [ ! -f "$CONSUL_CONFIG_PATH/certs/vault.key" ]
  then
    get_ssm_parameter $ssm_parameter_consul_tls_key | base64 -d > "$CONSUL_CONFIG_PATH/certs/vault.key"
    chown consul:consul "$CONSUL_CONFIG_PATH/certs/vault.key"
    chmod 0600 "$CONSUL_CONFIG_PATH/certs/vault.key"
    log "INFO" $func "The TLS key file path $CONSUL_CONFIG_PATH/certs/vault.key has been created..."
  else
    log "INFO" $func "The TLS key file path $CONSUL_CONFIG_PATH/certs/vault.key already exists. Doing nothing..."
  fi

  log "INFO" $func "Starting Consul service..."
  systemctl enable consul
  systemctl restart consul
}

function configure_vault {
  local -r func="configure_vault"

  log "INFO" $func "Creating Vault configuration file..."

  cat <<EOF > "$VAULT_CONFIG_PATH/config.hcl"
ui           = true
api_addr     = "https://$vault_api_address:8200"
cluster_addr = "https://$DEFAULT_IP_ADDRESS:8201"

storage "consul" {
  address = "127.0.0.1:8500"
  path    = "vault"
  # token   = "{{ consul_acl_token }}"
}

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = true
}

listener "tcp" {
  address       = "$DEFAULT_IP_ADDRESS:8200"
  tls_cert_file = "$VAULT_CONFIG_PATH/certs/vault.pem"
  tls_key_file  = "$VAULT_CONFIG_PATH/certs/vault.key"
}
EOF

  chmod 0640 "$VAULT_CONFIG_PATH/config.hcl"
  chown $username:$username "$VAULT_CONFIG_PATH/config.hcl"

  log "INFO" $func "Retrieving Vault TLS certificates..."
  assert_not_empty "--ssm-parameter-vault-tls-cert-chain" "$ssm_parameter_vault_tls_cert_chain"
  assert_not_empty "--ssm-parameter-vault-tls-key" "$ssm_parameter_vault_tls_key"

  if [ ! -f "$VAULT_CONFIG_PATH/certs/ca.pem" ]
  then
    get_ssm_parameter $ssm_parameter_vault_tls_ca | base64 -d > "$VAULT_CONFIG_PATH/certs/ca.pem"
    chown vault:vault "$VAULT_CONFIG_PATH/certs/ca.pem"
    chmod 0640 "$VAULT_CONFIG_PATH/certs/ca.pem"
    log "INFO" $func "The TLS CA chain file path $VAULT_CONFIG_PATH/certs/ca.pem has been created..."
  else
    log "INFO" $func "The TLS CA chain file path $VAULT_CONFIG_PATH/certs/ca.pem already exists. Doing nothing..."
  fi

  if [ ! -f "$VAULT_CONFIG_PATH/certs/vault.pem" ]
  then
    get_ssm_parameter $ssm_parameter_vault_tls_cert | base64 -d > "$VAULT_CONFIG_PATH/certs/vault.pem"
    chown vault:vault "$VAULT_CONFIG_PATH/certs/vault.pem"
    chmod 0640 "$VAULT_CONFIG_PATH/certs/vault.pem"
    log "INFO" $func "The TLS certificate file path $VAULT_CONFIG_PATH/certs/vault.pem has been created..."
  else
    log "INFO" $func "The TLS certificate file path $VAULT_CONFIG_PATH/certs/vault.pem already exists. Doing nothing..."
  fi

  if [ ! -f "$VAULT_CONFIG_PATH/certs/vault.key" ]
  then
    get_ssm_parameter $ssm_parameter_vault_tls_key | base64 -d > "$VAULT_CONFIG_PATH/certs/vault.key"
    chown vault:vault "$VAULT_CONFIG_PATH/certs/vault.key"
    chmod 0600 "$VAULT_CONFIG_PATH/certs/vault.key"
    log "INFO" $func "The TLS key file path $VAULT_CONFIG_PATH/certs/vault.key has been created..."
  else
    log "INFO" $func "The TLS key file path $VAULT_CONFIG_PATH/certs/vault.key already exists. Doing nothing..."
  fi

  log "INFO" $func "Starting Vault service..."
  systemctl enable vault
  systemctl restart vault
}

install=0
configure=0
consul_datacenter="dc1"
consul_server=0
vault_api_address="$DEFAULT_IP_ADDRESS"
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
    --consul-datacenter)
    consul_datacenter="$2"
    shift 2
    ;;
    --consul-server)
    consul_server=1
    shift
    ;;
    --consul-bootstrap-expect)
    consul_bootstrap_expect="$2"
    shift 2
    ;;
    --consul-rejoin-tag-key)
    consul_rejoin_tag_key="$2"
    shift 2
    ;;
    --consul-rejoin-tag-value)
    consul_rejoin_tag_value="$2"
    shift 2
    ;;
    --ssm-parameter-consul-tls-ca)
    ssm_parameter_consul_tls_ca="$2"
    shift 2
    ;;
    --ssm-parameter-consul-tls-cert)
    ssm_parameter_consul_tls_cert="$2"
    shift 2
    ;;
    --ssm-parameter-consul-tls-key)
    ssm_parameter_consul_tls_key="$2"
    shift 2
    ;;
    --vault-api-address)
    vault_api_address="$2"
    shift 2
    ;;
    --ssm-parameter-vault-tls-cert-chain)
    ssm_parameter_vault_tls_cert_chain="$2"
    shift 2
    ;;
    --ssm-parameter-vault-tls-key)
    ssm_parameter_vault_tls_key="$2"
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
  install_vault
  configure_consul
  configure_vault
elif [[ $install -eq 1 ]]
then
  install_consul
  install_vault
elif [[ $configure -eq 1 ]]
then
  configure_consul
  configure_vault
fi