#!/usr/bin/env bash

readonly CONFIG_PATH="/etc/vault"
readonly INSTALL_PATH="/usr/local/bin"

readonly SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"

readonly DEFAULT_IP_ADDRESS="$(ip address show $(ls -1 /sys/class/net | grep -v lo | sort -r | head -n 1) | awk '{print $2}' | egrep -o '([0-9]+\.){3}[0-9]+')"
readonly INSTANCE_ID="$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
readonly AWS_REGION="$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -c -r .region)"

source "$SCRIPT_PATH/funcs.sh"

install_vault() {
  local -r func="install_vault"

  create_user vault $CONFIG_PATH

  log "INFO" $func "Creating Vault directories..."
  mkdir "$CONFIG_PATH" "$CONFIG_PATH/certs"
  chmod 0750 "$CONFIG_PATH" "$CONFIG_PATH/certs"
  chown vault:vault "$CONFIG_PATH" "$CONFIG_PATH/certs"

  log "INFO" $func "Unpacking Vault..."
  cd "$INSTALL_PATH" && unzip -qu "$SCRIPT_PATH/vault.zip"
  chown vault:vault vault
  chmod 0755 vault
  setcap cap_ipc_lock=+ep vault

  log "INFO" $func "Creating Vault service..."
  cat > /etc/systemd/system/vault.service <<EOF
[Unit]
Description="HashiCorp Vault - A tool for managing secrets"
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=$CONFIG_PATH/config.hcl

[Service]
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=$INSTALL_PATH/vault server -config $CONFIG_PATH/config.hcl
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

configure_vault() {
  local -r func="configure_vault"

  log "INFO" $func "Creating Vault configuration file..."

  cat <<EOF > "$CONFIG_PATH/config.hcl"
ui           = true
api_addr     = "https://$api_address:8200"
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
  address                  = "$DEFAULT_IP_ADDRESS:8200"
  tls_cert_file            = "$CONFIG_PATH/certs/vault.pem"
  tls_key_file             = "$CONFIG_PATH/certs/vault.key"
  tls_disable_client_certs = true
}

seal "awskms" {
  region     = "$AWS_REGION"
  kms_key_id = "$unseal_kms_key_arn"
}
EOF

  chmod 0640 "$CONFIG_PATH/config.hcl"
  chown vault:vault "$CONFIG_PATH/config.hcl"

  log "INFO" $func "Retrieving Vault TLS certificates..."
  assert_not_empty "--ssm-parameter-tls-cert-chain" "$ssm_parameter_tls_cert_chain"
  assert_not_empty "--ssm-parameter-tls-key" "$ssm_parameter_tls_key"

  if [ ! -f "$CONFIG_PATH/certs/vault.pem" ]
  then
    get_ssm_parameter $AWS_REGION $ssm_parameter_tls_cert_chain | base64 -d > "$CONFIG_PATH/certs/vault.pem"
    chown vault:vault "$CONFIG_PATH/certs/vault.pem"
    chmod 0640 "$CONFIG_PATH/certs/vault.pem"
    log "INFO" $func "The TLS certificate file path $CONFIG_PATH/certs/vault.pem has been created..."
  else
    log "INFO" $func "The TLS certificate file path $CONFIG_PATH/certs/vault.pem already exists. Doing nothing..."
  fi

  if [ ! -f "$CONFIG_PATH/certs/vault.key" ]
  then
    get_ssm_parameter $AWS_REGION $ssm_parameter_tls_key | base64 -d > "$CONFIG_PATH/certs/vault.key"
    chown vault:vault "$CONFIG_PATH/certs/vault.key"
    chmod 0600 "$CONFIG_PATH/certs/vault.key"
    log "INFO" $func "The TLS key file path $CONFIG_PATH/certs/vault.key has been created..."
  else
    log "INFO" $func "The TLS key file path $CONFIG_PATH/certs/vault.key already exists. Doing nothing..."
  fi

  log "INFO" $func "Starting Vault service..."
  systemctl enable vault
  systemctl restart vault
}

install=0
configure=0
api_address="$DEFAULT_IP_ADDRESS"
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
    --api-address)
    api_address="$2"
    shift 2
    ;;
    --ssm-parameter-tls-cert-chain)
    ssm_parameter_tls_cert_chain="$2"
    shift 2
    ;;
    --ssm-parameter-tls-key)
    ssm_parameter_tls_key="$2"
    shift 2
    ;;
    --unseal-kms-key-arn)
    unseal_kms_key_arn="$2"
    shift 2
    ;;
    *)
    log "ERROR" $func "Bad argument $key"
    ;;
  esac
done

if [[ ($install -eq 1) && ($configure -eq 1) ]]
then
  install_vault
  configure_vault
elif [[ $install -eq 1 ]]
then
  install_vault
elif [[ $configure -eq 1 ]]
then
  configure_vault
fi