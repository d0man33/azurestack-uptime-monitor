#!/bin/bash

# Source functions.sh
source /azs/cli/shared/functions.sh \
  && echo "Sourced functions.sh" \
  || { echo "Failed to source functions.sh" ; exit 1 ; }

azs_job_start
################################## Task: Auth #################################
azs_task_start auth

# Login to Azure Stack cloud 
# Provide argument "adminmanagement" for authenticating to admin endpoint
# Provide argument "management" for authenticating to tenant endpoint
azs_login adminmanagement

azs_task_end auth
################################## Task: Read #################################
azs_task_start read

TENANT_SUBSCRIPTIONID=$(cat /run/secrets/cli | jq -r '.tenantSubscriptionId')
AZURE_SUBSCRIPTIONID=$(cat /run/secrets/cli | jq -r '.azureSubscriptionId')
API_VERSION_UPDATE_ADMIN="2016-05-01"

# Get update location
UPDATE_LOCATION_ID=$(az resource list \
      --resource-type "Microsoft.Update.Admin/updateLocations" \
      | jq -r ".[0].id") \
  && azs_log_field T status admin_pnu_update_location_id \
  || azs_log_field T status admin_pnu_update_location_id fail

# Get update location status
UPDATE_LOCATION_STATUS=$(az resource show --ids $UPDATE_LOCATION_ID) \
  && azs_log_field T status admin_pnu_update_location_status \
  || azs_log_field T status admin_pnu_update_location_status fail

# Get current update version
CURRENT_UPDATE_VERSION=$(echo $UPDATE_LOCATION_STATUS \
      | jq -r ".properties.currentVersion") \
  && azs_log_field N status admin_pnu_current_version \
  || azs_log_field N status admin_pnu_current_version fail

# Get current update status
CURRENT_UPDATE_STATE=$(echo $UPDATE_LOCATION_STATUS \
      | jq -r ".properties.state") \
  && azs_log_field T status admin_pnu_current_state \
  || azs_log_field T status admin_pnu_current_version fail

# Get Token for API call
TOKEN=$(az account get-access-token | jq -r ".accessToken") \
  && azs_log_field T status admin_pnu_get_token \
  || azs_log_field T status admin_pnu_get_token fail

ALL_UPDATES=$(curl -sX GET \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        https://adminmanagement.$(cat /run/secrets/cli | jq -r '.fqdn')"$UPDATE_LOCATION_ID"/updates?api-version="$API_VERSION_UPDATE_ADMIN" \
        | jq '[.value[]]') \
  && azs_log_field T status admin_pnu_get_updates \
  || azs_log_field T status admin_pnu_get_updates fail

# Sort by version
ALL_UPDATES_SORT=$(echo $ALL_UPDATES | jq 'sort_by(.properties.version) | reverse') \
  && azs_log_field T status admin_pnu_sort_updates \
  || azs_log_field T status admin_pnu_sort_updates fail

# OrderByUpdateVersion

# Select details from corresponding update
case "$CURRENT_UPDATE_STATE" in
  "UpdateAvailable")
    # Select Microsoft updates, Select the latest version.
    NEW_UPDATE=$(echo $ALL_UPDATES_SORT | jq '[.[] | select (.properties.publisher=="Microsoft") | select (.properties.state=="Ready")][0]')
    NEW_UPDATE_TEXT="and the latest version ready to be applied is"
    ;;
  "UpdateInProgress")
    # Select Microsoft updates, Select the latest version.
    NEW_UPDATE=$(echo $ALL_UPDATES_SORT | jq '[.[] | select (.properties.publisher=="Microsoft") | select(.properties.state=="Installing")][0]')
    NEW_UPDATE_TEXT="and the new version that is installing is"
    ;;
  "AppliedSuccessfully")
    # Select Microsoft updates, Select the latest version.
    NEW_UPDATE=$(echo $ALL_UPDATES_SORT | jq '[.[] | select (.properties.publisher=="Microsoft") | select(.properties.state=="Installed")][0]')
    NEW_UPDATE_TEXT="and the version that applied succesfully is"
    ;;
  "UpdateFailed")
    # If needed, order by date. Select the latest one.
    NEW_UPDATE=$(echo $ALL_UPDATES_SORT | jq '[.[] | select (.properties.publisher=="Microsoft") | select(.properties.state=="InstallationFailed")][0]')
    NEW_UPDATE_TEXT="and the version that failed to install is"
    ;;
esac

NEW_UPDATE_VERSION=$(echo $NEW_UPDATE | jq -r ".properties.version")
NEW_UPDATE_DESCRIPTION=$(echo $NEW_UPDATE | jq -r ".properties.description")

# Update admin_pnu measurement in InfluxDB
azs_log_field T pnu_current_update_version "$CURRENT_UPDATE_VERSION"
azs_log_field T pnu_current_update_state "$CURRENT_UPDATE_STATE"
azs_log_field T pnu_new_update_version "$NEW_UPDATE_VERSION"
azs_log_field T pnu_new_update_description "$NEW_UPDATE_DESCRIPTION"

echo "## Task: Create Annotations"

# Get the latest annotation from range_pnu meansurement in the influxDB
# to validate if it exists
RANGE_LAST=$(curl -s -G 'http://influxdb:8086/query?db=azs' \
      --data-urlencode 'q=SELECT * FROM "range_pnu" GROUP BY * ORDER BY DESC LIMIT 1') \
  && azs_log_field T status admin_pnu_get_last_from_influx \
  || azs_log_field T status admin_pnu_get_last_from_influx fail

RANGE_NEW_BODY=$(cat << END
{
  "time":$(($(date --utc +%s)*1000)),
  "timeEnd":$(($(date --utc +%s)*1000)),
  "isRegion":true,
  "tags":["$CURRENT_UPDATE_STATE","$NEW_UPDATE_VERSION"],
  "text":"Current update version is $CURRENT_UPDATE_VERSION $NEW_UPDATE_TEXT $NEW_UPDATE_DESCRIPTION"
}
END
)

# If no results are returned
if [[ $(echo "$RANGE_LAST" | jq -r ".results[].series") = "null" ]]
then

  # Write new annotation to Grafana (no need to update existing one since it doesn't exist yet)
  # Capture the result in a variable for the annotation Id
  RANGE_NEW_ID=$(curl -sX POST \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -u $(cat /run/secrets/cli | jq -r '.adminUsername'):$(cat /run/secrets/cli | jq -r '.grafanaPassword') \
        -d "$RANGE_NEW_BODY" http://grafana:3000/api/annotations | jq -r ".id") \
    && azs_log_field T status admin_pnu_new_range_grafana \
    || azs_log_field T status admin_pnu_new_range_grafana fail

  # Write new annotation to the Influx (no need to update existing one, since it doesn't exist yet)
  curl -s -i -XPOST "http:/influxdb:8086/write?db=azs&precision=s" \
        --data-binary "range_pnu tenant_subscriptionid=\"$TENANT_SUBSCRIPTIONID\",azure_subscriptionid=\"$AZURE_SUBSCRIPTIONID\",range_id=\"$RANGE_NEW_ID\",time_start=$(($(date --utc +%s)*1000)),state=\"$CURRENT_UPDATE_STATE\",current_version=\"$CURRENT_UPDATE_VERSION\",new_version=\"$NEW_UPDATE_VERSION\",new_description=\"$NEW_UPDATE_DESCRIPTION\"" | grep HTTP \
    && azs_log_field T status admin_pnu_new_range_influx \
    || azs_log_field T status admin_pnu_new_range_influx fail

else 

  # Get the latest annotation from range_pnu meansurement in the influxDB, selecting the values from the result
  RANGE_LAST=$(curl -s -G 'http://influxdb:8086/query?db=azs&epoch=s' \
        --data-urlencode 'q=SELECT range_id, time_start, state, current_version, new_version, new_description FROM "range_pnu" GROUP BY * ORDER BY DESC LIMIT 1' | jq -r ".results[].series[].values[]") \
    && azs_log_field T status admin_pnu_new_range_influx \
    || azs_log_field T status admin_pnu_new_range_influx fail

  RANGE_LAST_TIMESTAMP=$(echo $RANGE_LAST | jq -r ".[0]")
  RANGE_LAST_ID=$(echo $RANGE_LAST | jq -r ".[1]")
  RANGE_LAST_TIME_START=$(echo $RANGE_LAST | jq -r ".[2]")
  RANGE_LAST_STATE=$(echo $RANGE_LAST | jq -r ".[3]")
  RANGE_LAST_CURRENT_VERSION=$(echo $RANGE_LAST | jq -r ".[4]")
  RANGE_LAST_NEW_VERSION=$(echo $RANGE_LAST | jq -r ".[5]")
  RANGE_LAST_NEW_DESCRIPTION=$(echo $RANGE_LAST | jq -r ".[6]")

  RANGE_UPDATE_BODY=$(cat << END
{
  "time":$RANGE_LAST_TIME_START,
  "timeEnd":$(($(date --utc +%s)*1000)),
  "isRegion":true,
  "tags":["$RANGE_LAST_STATE","$RANGE_LAST_NEW_VERSION"],
  "text":"Current update version is $RANGE_LAST_CURRENT_VERSION $NEW_UPDATE_TEXT $RANGE_LAST_NEW_DESCRIPTION"
}
END
)

  # Update the existing annotation endTime in the Grafana db
  curl -sX PUT -H 'Content-Type: application/json' \
        -H 'Accept: application/json' \
        -u $(cat /run/secrets/cli | jq -r '.adminUsername'):$(cat /run/secrets/cli | jq -r '.grafanaPassword') \
        -d "$RANGE_UPDATE_BODY" http://grafana:3000/api/annotations/$RANGE_LAST_ID \
    && azs_log_field T status admin_pnu_update_range_grafana \
    || azs_log_field T status admin_pnu_update_range_grafana fail

  # Updating the influxDB entry with the new endtime
  curl -s -i -XPOST "http:/influxdb:8086/write?db=azs&precision=s" \
        --data-binary "range_pnu time_end=$(($(date --utc +%s)*1000)) $RANGE_LAST_TIMESTAMP" | grep HTTP \
    && azs_log_field T status admin_pnu_update_range_influx \
    || azs_log_field T status admin_pnu_update_range_influx fail
  
  # If the state changed
  if [ "$CURRENT_UPDATE_STATE" != "$RANGE_LAST_STATE" ]; then
    
    # Create new annotation
    RANGE_NEW_ID=$(curl -sX POST -H "Accept: application/json" \
          -H "Content-Type: application/json" \
          -u $(cat /run/secrets/cli | jq -r '.adminUsername'):$(cat /run/secrets/cli | jq -r '.grafanaPassword') \
          -d "$RANGE_NEW_BODY" http://grafana:3000/api/annotations | jq -r ".id") \
      && azs_log_field T status admin_pnu_new_state_grafana \
      || azs_log_field T status admin_pnu_new_state_grafana fail

    # Write new annotation to the Influx
    curl -s -i -XPOST "http:/influxdb:8086/write?db=azs&precision=s" \
          --data-binary "range_pnu tenant_subscriptionid=\"$TENANT_SUBSCRIPTIONID\",azure_subscriptionid=\"$AZURE_SUBSCRIPTIONID\",range_id=\"$RANGE_NEW_ID\",time_start=$(($(date --utc +%s)*1000)),state=\"$CURRENT_UPDATE_STATE\",current_version=\"$CURRENT_UPDATE_VERSION\",new_version=\"$NEW_UPDATE_VERSION\",new_description=\"$NEW_UPDATE_DESCRIPTION\"" | grep HTTP \
      && azs_log_field T status admin_pnu_new_state_influx \
      || azs_log_field T status admin_pnu_new_state_influx fail

  fi  
fi

azs_task_end read
############################### Job: Complete #################################
azs_job_end