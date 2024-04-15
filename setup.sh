#!/bin/bash


# --- installer configuration ---

SOURCE_DIR="src/*"
INSTALL_DIR="/usr/local/bin"
CONFIG_FILE="src/settings.conf"

# -------------------------------

# for colorful outputs
source src/prefix.sh

echo -e "$DEBUG Setting up logging..."



# Ensure that the influx configuration is set up correctly
INFLUX_CONFIG_NAME=$(influx config | sed -n '2p' | awk '{print $2}')
if [ "$INFLUX_CONFIG_NAME" != "logging_conf" ]
then
    # Try to enable the logging configuration
    influx config logging_conf
    if [ $? -eq 0 ]
    then
        echo -e "$DEBUG Set influx logging configuration as active configuration."
    else
        echo -e "$ERROR The influx configuration is not setup correctly. You can check the active config by running 'sudo influx config list'. The logging configuration needs to be named 'logging_conf'. If it is not present, please create it with 'sudo influx config create --config-name logging_conf --org <your_org> --token <your_token> --host-url http://localhost:8086 --active'. Please note that you also need to run this script with sudo permissions, otherwise the influx config cannot be accessed."
        exit 1
    fi
fi

# check if bucket exists
source src/settings.conf
if influx bucket list | grep -q "$BUCKET_NAME"
then
    echo -e "$SUCCESS Influx is setup correctly"
else
    echo -e "$DEBUG Creating bucket for logging."
    if ! influx bucket create -n $BUCKET_NAME
    then
        echo -e "$ERROR Could not create logging bucket. Probably, you did not provide an all-access token (which is a good idea). However, that means that you need to perform one manual step. Please create a bucket called $BUCKET_NAME yourself (and make sure the influx conf can access this bucket), or change the bucket name to an existing bucket in the configuration file located in '$CONFIG_FILE'"
        exit 1
    fi
fi


TARGET_KEY="RPI_NAME"
# Get command line arguments (if provided)
if ! [ $# -eq 0 ]
then
    REPLACEMENT_VALUE=$1
    sed -i "s/\($TARGET_KEY *= *\).*/\1\"$REPLACEMENT_VALUE\"/" $CONFIG_FILE
fi


echo -e "$DEBUG Copying files..."
# copy logging files to install directory
if cp -r $SOURCE_DIR $INSTALL_DIR; then
    echo -e "$SUCCESS Copied all files."
else
    echo -e "$ERROR Could not copy files. Please check if you have superuser privileges."
    exit 1
fi

echo -e "$DEBUG Setup system service..."
cd /etc/systemd/system

# get current user
USER=$(whoami)

# Setup service script
CONTENTS="[Unit]\n"
CONTENTS=$CONTENTS"Description=influx logging service\n"
CONTENTS=$CONTENTS"After=network.target\n"
CONTENTS=$CONTENTS"StartLimitIntervalSec=0\n"
CONTENTS=$CONTENTS"\n"
CONTENTS=$CONTENTS"[Service]\n"
CONTENTS=$CONTENTS"Type=simple\n"
CONTENTS=$CONTENTS"Restart=always\n"
CONTENTS=$CONTENTS"RestartSec=1\n"
CONTENTS=$CONTENTS"User=$USER\n"
CONTENTS=$CONTENTS"ExecStart=bash $INSTALL_DIR/logging.sh\n"
CONTENTS=$CONTENTS"\n"
CONTENTS=$CONTENTS"[Install]\n"
CONTENTS=$CONTENTS"WantedBy=multi-user.target\n"

# Write contents to file
if sudo echo -e $CONTENTS>"rpi_logging.service"; then
    echo -e "$SUCCESS Created system service."
fi

# make this logging start when the device is booted
if sudo systemctl enable rpi_logging.service; then
    echo -e "$SUCCESS Added system service to automatically start on boot."
fi

# Finally start service
if sudo systemctl restart rpi_logging; then
    echo -e "$SUCCESS Started logging."
fi

