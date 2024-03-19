#!/bin/bash


# --- installer configuration ---

SOURCE_DIR="src/*"
INSTALL_DIR="/usr/local/bin"

# -------------------------------

# for colorful outputs
source src/prefix.sh

echo -e "$DEBUG Setting up logging..."


echo -e "$DEBUG Copying files..."
# copy logging files to install directory
if cp -r $SOURCE_DIR $INSTALL_DIR; then
    echo -e "$SUCCESS Copied all files."
else
    echo -e "$ERROR Could not copy files. Please check if you have superuser priviliges."
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
if sudo systemctl start rpi_logging; then
    echo -e "$SUCCESS Started logging."
fi

