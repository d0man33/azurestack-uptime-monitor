#!/bin/bash

# Source functions.sh
source /azs/cli/shared/functions.sh \
  && echo "Sourced functions.sh" \
  || { echo "Failed to source functions.sh" ; exit 1 ; }

azs_job_start
################################# Task: CSV ###################################
azs_task_start csv

# To specify a specific to export run ./srv_csv.sh year week
# E.g. srv_csv.sh 2019 5
# If no argumetns are passed the script exports last weeks data

YEAR=${1:-$(date --utc +%G)}
WEEK=${2:-$(( $(date --utc +%-V) - 1 ))}
ONE_DAY_IN_SEC=86400

# Base Epoch date for year and week in seconds 
EPOCH_BASE_IN_SEC=$((  \
    $(date --utc -d "$YEAR-01-01" +%s) \
    + $(( \
        (( $WEEK * 7 + 1 - $(date -d "$YEAR-01-04" +%w ) - 3 )) \
        * $ONE_DAY_IN_SEC \
    )) \
    - $(( 2 * $ONE_DAY_IN_SEC )) \
)) \
  && azs_log_field T status srv_export_csv_epoch_base \
  || azs_log_field T status srv_export_csv_epoch_base fail

# Add one day to base for start
EPOCH_START_IN_SEC=$(( \
    $EPOCH_BASE_IN_SEC + $(( 1 * $ONE_DAY_IN_SEC )) \
)) \
  && azs_log_field T status srv_export_csv_epoch_start \
  || azs_log_field T status srv_export_csv_epoch_start fail

# Add 8 days minus 1 sec for end 
EPOCH_END_IN_SEC=$(( \
    $EPOCH_BASE_IN_SEC + $(( 8 * $ONE_DAY_IN_SEC )) - 1 \
)) \
  && azs_log_field T status srv_export_csv_epoch_end \
  || azs_log_field T status srv_export_csv_epoch_end fail

# Set filename
WEEK_FMT=0$WEEK
WEEK_FMT="${WEEK_FMT: -2}"
CSV_FILE_NAME=$(cat /run/secrets/cli | jq -r '.tenantSubscriptionId')-y${YEAR}w${WEEK_FMT}

# Export data to file
curl -G 'http://influxdb:8086/query?db=azs' \
      --data-urlencode "q=SELECT * FROM /.*/ where time >= ${EPOCH_START_IN_SEC}s and time <= ${EPOCH_END_IN_SEC}s" \
      -H "Accept: application/csv" \
      -o /azs/cli/export/$CSV_FILE_NAME.csv \
  && azs_log_field T status srv_export_csv_to_file \
  || azs_log_field T status srv_export_csv_to_file fail

azs_task_end csv
############################### Job: Complete #################################
azs_job_end