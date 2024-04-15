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
    CPU_usage=$(grep 'cpu ' /proc/stat | awk '{print 100*($2+$4)/($2+$4+$5)}')
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
    DATA_STRING=$DATA_STRING$'\n'"$MEASUREMENT_NAME,device=$RPI_NAME,unit=celsius cpu_temp=$CPU_temp"
    # add RAM usage
    DATA_STRING=$DATA_STRING$'\n'"$MEASUREMENT_NAME,device=$RPI_NAME,unit=kB RAM_total=$RAM_totl"
    DATA_STRING=$DATA_STRING$'\n'"$MEASUREMENT_NAME,device=$RPI_NAME,unit=kB RAM_used=$RAM_used"
    DATA_STRING=$DATA_STRING$'\n'"$MEASUREMENT_NAME,device=$RPI_NAME,unit=kB RAM_free=$RAM_free"

    # add data from DU
    get_DU

    #send to influx
    influx write --bucket $BUCKET_NAME "$DATA_STRING"
}


echo -e "$DEBUG Starting logging service."
while true
do
    # https://unix.stackexchange.com/questions/52313/how-to-get-execution-time-of-a-script-effectively
    # print output purely as seconds
    TIMEFORMAT=%R
    execution_time=$( { time log_influx; } 2>&1 )

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



