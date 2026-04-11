#!/bin/bash

# Installs InfluxDB v2 CLI
#
# This installation follows the official documentation located at
# https://docs.influxdata.com/influxdb/cloud/reference/cli/influx/?t=Linux

# import log prefix
source src/prefix.sh

INSTALL_FOLDER=install_flux

mkdir -p $INSTALL_FOLDER

# create a trap to remove this temporary install folder upon exit
trap "rm -r $INSTALL_FOLDER" EXIT SIGHUP SIGINT SIGTERM


echo -e "$DEBUG Installing Influx CLI"
# install CLI
arch=$(uname -m)
if [[ "$arch" == "x86_64" ]]; then
    # amd64
    curl -O --output-dir $INSTALL_FOLDER https://dl.influxdata.com/influxdb/releases/influxdb2-client-2.7.5-linux-amd64.tar.gz
    FILENAME="influxdb2-client-2.7.5-linux-amd64.tar.gz"
    HASH=496dffcd70bed2bb3dc3d614e3d9c97e312e092dfe0577d332027566bbb7d8cd
elif [[ "$arch" == "aarch64" ]]; then
    # arm
    curl -O --output-dir $INSTALL_FOLDER  https://dl.influxdata.com/influxdb/releases/influxdb2-client-2.7.5-linux-arm64.tar.gz
    FILENAME="influxdb2-client-2.7.5-linux-arm64.tar.gz"
    HASH=867c3cbabd63a34a9b1ac643fd5c5d268b694acc98e3b75fa5a78d63037097dd
else
    echo -e "$ERROR Unknown architecture (Found: $arch, supported: amd64 and arm64). Please install influx CLI manually."
    exit 1
fi


# check hash after downloading
echo -e "$DEBUG Checking SHA256 signature..."
if echo "$HASH $INSTALL_FOLDER/$FILENAME" | sha256sum --quiet -c -; then
    # unpack
    tar xzf $INSTALL_FOLDER/$FILENAME -C $INSTALL_FOLDER
    # copy files
    sudo cp $INSTALL_FOLDER/influx /usr/local/bin/
else
    # abort and print Warning
    echo -e "$ERROR Hashsum of influx CLI installer is incorrect! Aborting installation!"
    exit 1
fi


echo -e "$SUCCESS Installed Influx CLI"
echo -e "$SUCCESS You can access it by running: influx"
