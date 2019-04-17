#!/usr/bin/env bash

log() {
  local -r level="$1"
  local -r func="$2"
  local -r message="$3"
  local -r timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  >&2 echo -e "${timestamp} [${level}] [${SCRIPT_NAME}:${func}] ${message}"
  [ "$level" == "ERROR" ] && exit 1
}

assert_not_empty() {
  local -r func="assert_not_empty"
  local -r arg_name="$1"
  local -r arg_value="$2"

  if [[ -z "$arg_value" ]]; then
    log "ERROR" "$func" "The value for '$arg_name' cannot be empty"
    print_usage
    exit 1
  fi
}

user_exists() {
  local -r func="user_exists"
  local -r user="$1"
  id "$user" >/dev/null 2>&1
}

create_user() {
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

get_ssm_parameter() {
  local -r func="get_ssm_parameter"
  local -r region="$1"
  local -r parameter="$2"
  
  log "INFO" $func "Retrieving SSM parameter $parameter..."
  aws --region "$region" ssm get-parameter --name "$parameter" --with-description | jq --raw-output '.Parameter.Value'
}