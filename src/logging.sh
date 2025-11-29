#!/bin/bash

# Runs logging on the Raspberry Pi
#
# This code evaluates the CPU and RAM usage, as well as the current storage usage (SD card).
# This data is then sent to influx

# import log prefix
source prefix.sh

# ---- Logging Configuration from settings.conf ----

source settings.conf

# --------------------------------------------------


# define functions for obtaining system stats
get_network_usage() {
  local interface=$1
  local usage_file="/tmp/network_usage_$interface"
  local rx_prev tx_prev rx_curr tx_curr rx_rate tx_rate rx_rate_kbits tx_rate_kbits

  rx_prev=$(cat /sys/class/net/$interface/statistics/rx_bytes)
  tx_prev=$(cat /sys/class/net/$interface/statistics/tx_bytes)

  while true; do
    sleep 1
    rx_curr=$(cat /sys/class/net/$interface/statistics/rx_bytes)
    tx_curr=$(cat /sys/class/net/$interface/statistics/tx_bytes)
    rx_rate=$((rx_curr - rx_prev))
    tx_rate=$((tx_curr - tx_prev))
    echo "RX_KBPS=$((rx_rate * 8 / 1000))" > "$usage_file"
    echo "TX_KBPS=$((tx_rate * 8 / 1000))" >> "$usage_file"
    rx_prev=$rx_curr
    tx_prev=$tx_curr
  done &
}

# Loop through all network interfaces
for interface in $(ls /sys/class/net/); do
  if [[ "$interface" != "lo" ]]; then
    get_network_usage $interface
  fi
done


get_Network () {
    # Loop through all network interfaces
    for interface in $(ls /sys/class/net/); do
        if [[ "$interface" != "lo" ]]; then
            usage_file="/tmp/network_usage_$interface"
            if [[ -f "$usage_file" ]]; then
                rx_kbps=$(grep -oP '^RX_KBPS=\K[0-9]+' "$usage_file")
                tx_kbps=$(grep -oP '^TX_KBPS=\K[0-9]+' "$usage_file")
                DATA_STRING=$DATA_STRING$'\n'"$MEASUREMENT_NAME,device=$RPI_NAME,unit=kB/s,interface=$interface tx=${rx_kbps}"
                DATA_STRING=$DATA_STRING$'\n'"$MEASUREMENT_NAME,device=$RPI_NAME,unit=kB/s,interface=$interface rx=${tx_kbps}"
            fi
        fi
    done
}

get_RAM () {
    # RAM USAGE
    RAM_totl=$(free | sed -n '2{p;q}' | awk '{print $2}')
    RAM_used=$(free | sed -n '2{p;q}' | awk '{print $3}')
    RAM_free=$(free | sed -n '2{p;q}' | awk '{print $4}')
}

get_CPU () {
    # CPU Usage
    # CPU information: cpu <user> <nice> <system> <idle> <iowait> <irq> <softirq>
    #                   $1   $2    $3      $4       $5     $6      $7      $8
    CPU_usage=$(awk '{u=$2+$4; t=$2+$4+$5; if (NR==1){u1=u; t1=t;} else print ($2+$4-u1) * 1000 / (t-t1); }' <(grep 'cpu ' /proc/stat) <(sleep 0.1; grep 'cpu ' /proc/stat))
}

get_CPU_temp () {
    CPU_temp=$(echo "scale=3; $(</sys/class/thermal/thermal_zone0/temp)/1000" | bc)
}

get_DU () {
    # Disk usage
    # Run the df command and skip the first line
    df_output=$(df | sed -n '2,$p')

    # Loop over each line in the df output
    while IFS= read -r line; do
        # gather data
        partname=$(echo $line| awk '{print $1}')

        # we do not want to log temporary partitions and also ignore the virtual udev partition
        if [ "$partname" != "tmpfs" ] && [ "$partname" != "udev" ]
        then
            mem_totl=$(echo $line| awk '{print $2}')
            mem_used=$(echo $line| awk '{print $3}')
            mem_free=$(echo $line| awk '{print $4}')

            # append to data string directly
            DATA_STRING=$DATA_STRING$'\n'"$MEASUREMENT_NAME,device=$RPI_NAME,unit=kB,partition=$partname mem_total=$mem_totl"
            DATA_STRING=$DATA_STRING$'\n'"$MEASUREMENT_NAME,device=$RPI_NAME,unit=kB,partition=$partname mem_used=$mem_used"
            DATA_STRING=$DATA_STRING$'\n'"$MEASUREMENT_NAME,device=$RPI_NAME,unit=kB,partition=$partname mem_free=$mem_free"
        fi

    # done
    done <<< "$df_output"
}



# send data to influx
log_influx () {
    # get data
    get_CPU
    get_CPU_temp
    get_RAM

    # add CPU usage
    DATA_STRING="$MEASUREMENT_NAME,device=$RPI_NAME,unit=percent cpu_usage=$CPU_usage"
    # add CPU temperature
    if [[ "$CPU_temp" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        DATA_STRING=$DATA_STRING$'\n'"$MEASUREMENT_NAME,device=$RPI_NAME,unit=celsius cpu_temp=$CPU_temp"
    fi    
    # add RAM usage
    DATA_STRING=$DATA_STRING$'\n'"$MEASUREMENT_NAME,device=$RPI_NAME,unit=kB RAM_total=$RAM_totl"
    DATA_STRING=$DATA_STRING$'\n'"$MEASUREMENT_NAME,device=$RPI_NAME,unit=kB RAM_used=$RAM_used"
    DATA_STRING=$DATA_STRING$'\n'"$MEASUREMENT_NAME,device=$RPI_NAME,unit=kB RAM_free=$RAM_free"

    # add data from DU
    get_DU

    # add Network usage
    get_Network

    #send to influx
    influx write --bucket $BUCKET_NAME "$DATA_STRING"
}


echo -e "$DEBUG Starting logging service."
while true
do
    # https://unix.stackexchange.com/questions/52313/how-to-get-execution-time-of-a-script-effectively
    # print output purely as seconds
    TIMEFORMAT=%R
    # execution_time=$( { time log_influx; } 2>&1 )
    execution_time=$( { time log_influx > /dev/null 2>&1; } 2>&1 )

    if $PRINT_DEBUG
    then
        echo -e "$DEBUG gathering and sending data took $execution_time""s"
    fi

    
    # require the duration of the logging to be less than 10% of the allocated wait time to adjust load on the system
    result=$(echo "$execution_time * 10" | bc)
    if (( $(echo "$result > $SLEEP_TIME" |bc -l) ));
    then
        SLEEP_TIME=$((SLEEP_TIME*2))
        echo -e "$WARNING System seems busy, reducing load from logging by increasing idle time to $SLEEP_TIME""s"
    fi

    # if we are way faster than the idle time we increase the logging speed
    result=$(echo "$execution_time * 50" | bc)
    if (( $(echo "$result < $SLEEP_TIME" |bc -l) ));
    then
        SLEEP_TIME=$((SLEEP_TIME/2))
        echo -e "$SUCCESS The performance seems great, we increase the logging speed to $SLEEP_TIME""s"
    fi

    sleep $SLEEP_TIME
done



