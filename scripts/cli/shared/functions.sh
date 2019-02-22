#!/bin/bash

function azs_log_field
{
  # Field type is either N or T.
  # N is used for a number (for creating graphs)
  # T Text needs to be escaped in the Line Protocol
  local FIELD_VALUE_TYPE=$1

  # Field name can be job (indicating the start or the completion of the full job)
  # can be the name of the task within a job (e.g. auth)
  # or can be the name of another field to add (e.g. version)
  local FIELD_NAME=$2

  # -1 indicated the job or jobtask is starting, 1 indicates its completed
  local FIELD_VALUE=$3
  
  if [ "$FIELD_VALUE_TYPE" == "N" ]; then 
    echo "## Task: azs_log_field N ${JOB_NAME} ${FIELD_NAME} ${FIELD_VALUE}"
    curl -s -i -XPOST "http://influxdb:8086/write?db=azs&precision=s" --data-binary "${JOB_NAME} ${FIELD_NAME}=${FIELD_VALUE} ${JOB_TIMESTAMP}" | grep HTTP
  fi

  if [ "$FIELD_VALUE_TYPE" == "T" ]; then
    echo "## Task: azs_log_field T ${JOB_NAME} ${FIELD_NAME} ${FIELD_VALUE}"
    curl -s -i -XPOST "http://influxdb:8086/write?db=azs&precision=s" --data-binary "${JOB_NAME} ${FIELD_NAME}=\"${FIELD_VALUE}\" ${JOB_TIMESTAMP}" | grep HTTP  
  fi

  # If there is a fourth argument with the value fail, then exit the container completely
  if [ "$4" == "fail" ]; then
   exit 1
  fi  
} 

function azs_log_runtime
{
  local TASK=$1 
  # can be job (indicating the start or the completion of the full job)
  # can be the name of the task within a job (e.g. auth)
  local STARTTIME=$2

  local RUNTIME=$(( $(date --utc +%s) - $STARTTIME ))
   
  echo "## Task: azs_log_runtime ${JOB_NAME} ${TASK}_runtime ${RUNTIME}"
  curl -s -i -XPOST "http://influxdb:8086/write?db=azs&precision=s" --data-binary "${JOB_NAME} ${TASK}_runtime=${RUNTIME} ${JOB_TIMESTAMP}" | grep HTTP 
} 

function azs_task_start
{
  # Action = probe, auth, create, read, update or delete
  local ACTION=$1
  
  echo "## Task start: $JOB_NAME $ACTION"
  # Set the starttime for the task
  START_TIME=$(date --utc +%s)

  # Write entry in DB indicating auth is starting
  azs_log_field N $ACTION 0
}

function azs_task_end
{
  # Action = probe, create, read, update or delete
  local ACTION=$1

  echo "## Task end: $JOB_NAME $ACTION"
  # Set the runtime for the task
  azs_log_runtime $ACTION $START_TIME
  azs_log_field N $ACTION 100
}

function azs_job_start
{
  echo "############ Date       : $(date)"
  echo "############ Job name   : $JOB_NAME"
  echo "############ Version    : $(cat /run/secrets/cli | jq -r '.scriptVersion')"

  # Update entry in the influxdb
  azs_log_field T azure_subscriptionid $(cat /run/secrets/cli | jq -r '.azureSubscriptionId')
  azs_log_field T tenant_subscriptionid $(cat /run/secrets/cli | jq -r '.tenantSubscriptionId')
  azs_log_field N script_version $(cat /run/secrets/cli | jq -r '.scriptVersion')
}

function azs_job_end
{
  [[ $JOB_NAME = "srv_csv" || $JOB_NAME = "debug_export" ]] \
  && [[ $(cat /run/secrets/cli | jq -r ".activationKey") != "null" ]] \
  && azs_bridge

  echo "## Job complete: $JOB_NAME"
  # Set the runtime for the job
  azs_log_runtime job $JOB_TIMESTAMP
  azs_log_field T status job_complete 
  azs_log_field N job 100
}

function azs_registration
{
  local ACCOUNT=$(echo $ARGUMENTS_JSON | jq -r ".activationKey" | base64 -d | jq -r ".account")
  [ $ACCOUNT != "azsuptime" ] && { echo "Activation key is invalid" ; exit 1 ; }

  if [ $FQDN = "local.azurestack.external" ]
  then 
    local FILENAME=deploy-asdk-$(date --utc +y%Gw%V-m%md%dh%Hm%M)-v$(sudo cat /azs/common/config.json | jq -r ".version.script").log
  else
    local FILENAME=deploy-$(echo $ARGUMENTS_JSON | jq -r ".tenantSubscriptionId")-$(date --utc +y%Gw%V-m%md%dh%Hm%M)-v$(sudo cat /azs/common/config.json | jq -r ".version.script").log
  fi

  echo "registration" > $FILENAME

  az storage blob upload \
        --container-name $(echo $ARGUMENTS_JSON | jq -r ".activationKey" | base64 -d | jq -r ".customer") \
        --account-name $ACCOUNT \
        --sas-token $(echo $ARGUMENTS_JSON | jq -r ".activationKey" | base64 -d | jq -r ".token") \
        --file $FILENAME \
        --name $FILENAME \
  && echo "## Pass: registration" \
  || { echo "## Fail: registration" ; exit 1 ; }
}

function azs_bridge
{
  local ACCOUNT=$(cat /run/secrets/cli | jq -r ".activationKey" | base64 -d | jq -r ".account")
  [ $ACCOUNT != "azsuptime" ] && { echo "Activation key is invalid" ; exit 1 ; }
  [ $FQDN = "local.azurestack.external" ] && { echo "Running on ASDK" ; return 0 ; }

  for F in $(ls /azs/cli/export)
  do 
    az storage blob upload \
          --container-name $(cat /run/secrets/cli | jq -r ".activationKey" | base64 -d | jq -r ".customer") \
          --account-name $ACCOUNT \
          --file /azs/cli/export/"$F" \
          --sas-token $(cat /run/secrets/cli | jq -r ".activationKey" | base64 -d | jq -r ".token") \
          --if-none-match "*" \
          --name $F \
          > /dev/null 2>&1 \
      && echo "Bridge: $F" \
      || echo "Exists: $F"
  done
}

function azs_login
{
  local FQDNHOST=$1

  # Set REQUESTS_CA_BUNDLE variable with ca bundle
  export REQUESTS_CA_BUNDLE=/azs/cli/shared/ca-bundle.crt \
    && azs_log_field T status auth_ca_bundle \
    || azs_log_field T status auth_ca_bundle fail

  ## Register cloud (cloud_register)
  az cloud register \
        --name AzureStackCloud \
        --endpoint-resource-manager "https://$FQDNHOST.$(cat /run/secrets/cli | jq -r '.fqdn')" \
        --suffix-storage-endpoint "$(cat /run/secrets/cli | jq -r '.fqdn')" \
        --profile "$(cat /run/secrets/cli | jq -r '.apiProfile')" \
    && azs_log_field T status auth_cloud_register \
    || azs_log_field T status auth_cloud_register fail

  ## Select cloud
  az cloud set \
        --name AzureStackCloud \
    && azs_log_field T status auth_select_cloud \
    || azs_log_field T status auth_cloud_register fail

  ## Sign in as SPN
  az login \
        --service-principal \
        --tenant $(cat /run/secrets/cli | jq -r '.tenantId') \
        --username $(cat /run/secrets/cli | jq -r '.appId') \
        --password $(cat /run/secrets/cli | jq -r '.appKey') \
    && azs_log_field T status auth_login \
    || azs_log_field T status auth_login fail

  ## If auth endpoint is management, then set tenantSubscriptionId for SPN
  if [ "$FQDNHOST" = "management" ]
  then
    az account set \
          --subscription $(cat /run/secrets/cli | jq -r '.tenantSubscriptionId') \
      && azs_log_field T status set_tenantsubscriptionid \
      || azs_log_field T status set_tenantsubscriptionid fail
  fi

  return 0
}