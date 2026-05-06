#!/bin/bash

# Let's ensure normal operation on exit or if interrupted ...
function fuCLEANUP {
  exit 0
}
trap fuCLEANUP EXIT

# Source ENVs from file ...
if [ -f "/data/tpot/etc/compose/elk_environment" ];
  then
    echo "Found .env, now exporting ..."
    set -o allexport
    source "/data/tpot/etc/compose/elk_environment"
    LS_SSL_VERIFICATION="${LS_SSL_VERIFICATION:-full}"
    set +o allexport
fi

# Check internet availability 
function fuCHECKINET () {
mySITES=$1
error=0
for i in $mySITES;
  do
    curl --connect-timeout 5 -Is $i 2>&1 > /dev/null
      if [ $? -ne 0 ];
        then
          let error+=1
      fi;
  done;
  echo $error
}

# Check for connectivity and download latest translation maps
# --- ONLY DOWNLOAD ON HIVE, NOT ON SENSORS ---
if [ "$TPOT_TYPE" != "SENSOR" ]; then
  myCHECK=$(fuCHECKINET "raw.githubusercontent.com")
  if [ "$myCHECK" == "0" ]; then
    echo "Connection to Listbot looks good, now downloading latest translation maps (HIVE only)."
    cd /etc/listbot 
    aria2c -s16 -x 16 https://raw.githubusercontent.com/SweetBaitAdmin/listbot-lists/main/cve.yaml.bz2 && \
    aria2c -s16 -x 16 https://raw.githubusercontent.com/SweetBaitAdmin/listbot-lists/main/iprep.yaml.bz2 && \
    bunzip2 -f *.bz2
    
    cd /
  else
    echo "Cannot reach Listbot, starting HIVE Logstash without latest translation maps."
  fi
else
  echo "SENSOR detected: Skipping Listbot map downloads to save resources."
fi
# ------------------------------------------------

# Distributed T-Pot installation needs a different pipeline config 
if [ "$TPOT_TYPE" == "SENSOR" ];
  then
    echo
    echo "Distributed T-Pot setup, sending T-Pot logs to $TPOT_HIVE_IP."
    echo
    echo "T-Pot type: $TPOT_TYPE"
    echo "Hive IP: $TPOT_HIVE_IP"
    echo "SSL verification: $LS_SSL_VERIFICATION"
    echo
    # --- CRITICAL MEMORY OVERRIDE SECTION FOR SENSORS ---
    export LS_JAVA_OPTS="-Xms128m -Xmx128m"
    
    ARCH=$(arch)
    if [ "$ARCH" = "aarch64" ]; then
      export _JAVA_OPTIONS="-Xms128m -Xmx128m -XX:UseSVE=0"
      echo "Detected ARM64 architecture. Applying -XX:UseSVE=0 flag."
    else
      export _JAVA_OPTIONS="-Xms128m -Xmx128m"
      echo "Detected x86_64 architecture. No SVE flag needed."
    fi
    
    unset JAVA_TOOL_OPTIONS
    echo "Starting Logstash with memory limits: 128MB min/max"
    # ----------------------------------------------------
   # Ensure correct file permissions for private keyfile or SSH will ask for password
    cp /usr/share/logstash/config/pipelines_sensor.yml /usr/share/logstash/config/pipelines.yml
fi

if [ "$TPOT_TYPE" != "SENSOR" ];
  then
    echo
    echo "This is a T-Pot STANDARD / HIVE installation."
    echo
    echo "T-Pot type: $TPOT_TYPE"
    echo

    # Index Management is happening through ILM, but we need to put T-Pot ILM setting on ES.
    myTPOTILM=$(curl -s -XGET "http://elasticsearch:9200/_ilm/policy/tpot" | grep "Lifecycle policy not found: tpot" -c)
    if [ "$myTPOTILM" == "1" ];
      then
        echo "T-Pot ILM template not found on ES, putting it on ES now."
        curl -XPUT "http://elasticsearch:9200/_ilm/policy/tpot" -H 'Content-Type: application/json' -d'
        {
          "policy": {
            "phases": {
              "hot": {
                "min_age": "0ms",
                "actions": {}
              },
              "delete": {
                "min_age": "30d",
                "actions": {
                  "delete": {
                    "delete_searchable_snapshot": true
                  }
                }
              }
            },
            "_meta": {
              "managed": true,
              "description": "T-Pot ILM policy with a retention of 30 days"
            }
          }
        }'
      else
        echo "T-Pot ILM already configured or ES not available."
    fi
fi
echo

# --- ARCHITECTURE FIX FOR HIVE (and any non-sensor node) ---
# If this is NOT a sensor (i.e., it's the HIVE), we still need to handle ARM specifics.
# We only add the SVE flag if we are on ARM.
if [ "$TPOT_TYPE" != "SENSOR" ]; then
  ARCH=$(arch)
  if [ "$ARCH" = "aarch64" ]; then
    # If _JAVA_OPTIONS is empty, set it.
    # If it's already set (e.g., by .env), we MUST append the flag to avoid losing other settings.
    if [ -z "$_JAVA_OPTIONS" ]; then
      export _JAVA_OPTIONS="-XX:UseSVE=0"
      echo "Detected ARM64 on HIVE. Setting _JAVA_OPTIONS='-XX:UseSVE=0'."
    else
      # Check if flag is already present to avoid duplicates
      if [[ "$_JAVA_OPTIONS" != *"UseSVE=0"* ]]; then
        export _JAVA_OPTIONS="${_JAVA_OPTIONS} -XX:UseSVE=0"
        echo "Detected ARM64 on HIVE. Appending -XX:UseSVE=0 flag."
      else
        echo "Detected ARM64 on HIVE. -XX:UseSVE=0 flag already present."
      fi
    fi
  fi
fi
# -----------------------------------------------------------

exec /usr/share/logstash/bin/logstash --config.reload.automatic
