# Logging for Raspberry Pi

## Short summary

This repository collects core vitals of any ubuntu based system and sends it to an influx database.
It is intended and written for a Raspberry Pi, however it should be applicable for any ubuntu based system.
Core vitals that are being logged:

- CPU usage
- CPU temperature
- RAM usage
- Disk usage of all mounted drives


## Installation

This repository contains a bash script to setup a system service, such that the logging runs in the background.
To run it, first just clone this repository

    git clone https://github.com/jangeiger/rpi_logging.git

Now you need to add a configuration for influx, such that this code can write data to the database.
Therefore, add a configuration via

    sudo influx config create --config-name logging_conf --org <your_org> --token <your_token> --host-url http://localhost:8086 --active

You need to insert the information for your org and an API token.
This code expects a bucked called `rpi_logging` to exist.
If you want to store the data in a different bucket, you can change the configuration in `src/logging.sh` and modify the variable `BUCKET_NAME`.
You can also adjust the device name there (`RPI_NAME`).

Lastly, once you have setup the influx configuration and adjusted the variables to your liking, install the logger by running the installer with

    sudo bash setup.sh

Optionally, you can provide a custom name to this device as the first command line argument.


## Checking the installation

One you have finished the installation, you can check if everything is working by running

    systemctl status rpi_logging

You should see the output 'Starting logging service.' on the bottom.


## Visualizing the data

You should also immediately see the logging data appearing in influx.
To nicely visualize the data, you can setup a grafana dashboard, that gives you a nice overview of the current status of your Pi.
