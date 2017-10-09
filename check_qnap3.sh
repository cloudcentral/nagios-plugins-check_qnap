#!/usr/bin/env bash
############################# Written and Manteined by Nicola Bandini     ###############
############################# Created and written by Matthias Luettermann ###############
############################# finetuning by primator@gmail.com
############################# finetuning by n.bandini@gmail.com
############################# with code by Tom Lesniak and Hugo Geijteman
#
#	copyright (c) 2008 Shahid Iqbal
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation;
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# contact the author directly for more information at: matthias@xcontrol.de
##########################################################################################
#Version 1.23
plgVer=1.23

if [ ! "$#" == "5" ]; then
	echo
	echo "Check_QNAP3 $plgVer"
	echo
	echo "Warning: Wrong command line arguments."
	echo
	echo "Usage: ${0##*/} <hostname> <community> <part> <warning> <critical>"
	echo
	echo "Parts are: status, sysinfo, systemuptime, temp, cpu, cputemp, freeram, powerstatus, fans, diskused, hdstatus, hd#status, hd#temp, volstatus (Raid Volume Status), vol#status"
	echo
	echo "hdstatus shows status & temp; volstatus checks all vols and vols space; powerstatus checks power supply"
	echo "<#> is 1-8 for hd, 1-5 for vol"
	echo
	echo " Example for diskusage: ${0##*/} 127.0.0.1 public diskused 80 95"
	echo
	echo " Example for volstatus: ${0##*/} 127.0.0.1 public volstatus 15 10"
	echo "                        critical and warning value are related to free disk space"
	echo
	echo " Example for fans: ${0##*/} 127.0.0.1 public fans 2000 1900"
	echo "                   critical and warning are minimum speed in rpm for fans"
	echo
	exit 3
fi

strHostname="$1"
strCommunity="$2"
strpart="$3"
strWarning="$4"
strCritical="$5"

function _snmpget() {
	snmpget -v 2c -c "$strCommunity" $strHostname "$@"
}

function _snmpgetval() {
	snmpget -v 2c -c "$strCommunity" -Oqv $strHostname "$@"
}

function _snmpstatus() {
	snmpstatus -v 2c -c "$strCommunity" $strHostname "$@"
}

function _get_exp() {
	case "$1" in
		PB)	echo "40" ;;
		TB)	echo "30" ;;
		GB)	echo "20" ;;
		MB)	echo "10" ;;
		'')	echo "0" ;;
		*)	echo "ERROR: unknown unit '$1'" ;;
	esac
}

# Check if QNAP is online
TEST="$(_snmpstatus -t 5 -r 0 2>&1)"
if [ "$TEST" == "Timeout: No Response from $strHostname" ]; then
	echo "CRITICAL: SNMP to $strHostname is not available or wrong community string";
	exit 2;
fi

# STATUS ---------------------------------------------------------------------------------------------------------------------------------------
if [ "$strpart" == "status" ]; then
	echo "$TEST";

# DISKUSED ---------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "diskused" ]; then
	diskStr="$(_snmpget 1.3.6.1.4.1.24681.1.2.17.1.4.1)"
	freeStr="$(_snmpget 1.3.6.1.4.1.24681.1.2.17.1.5.1)"

	diskSize="$(echo "$diskStr" | awk '{print $4}' | sed 's/.\(.*\)/\1/')"
	freeSize="$(echo "$freeStr" | awk '{print $4}' | sed 's/.\(.*\)/\1/')"
	diskUnit="$(echo "$diskStr" | awk '{print $5}' | sed 's/.*\(.B\).*/\1/')"
	freeUnit="$(echo "$freeStr" | awk '{print $5}' | sed 's/.*\(.B\).*/\1/')"

	diskExp="$(_get_exp "$diskUnit")"
	freeExp="$(_get_exp "$freeUnit")"

	disk="$(echo "scale=0; $diskSize*(2^$diskExp)" | bc -l)"
	free="$(echo "scale=0; $freeSize*(2^$freeExp)" | bc -l)"

	used="$(echo "scale=0; $disk-$free" | bc -l)"
	perc="$(echo "scale=0; $used*100/$disk" | bc -l)"

	diskH="$(echo "scale=2; $disk/(2^$diskExp)" | bc -l)"
	freeH="$(echo "scale=2; $free/(2^$freeExp)" | bc -l)"
	usedH="$(echo "scale=2; $used/(2^$diskExp)" | bc -l)"

	diskF="$diskH$diskUnit"
	freeF="$freeH$freeUnit"
	usedF="$usedH$diskUnit"

	#wdisk=$(echo "scale=0; $strWarning*$disk/100" | bc -l)
	#cdisk=$(echo "scale=0; $strCritical*$disk/100" | bc -l)

	OUTPUT="Total:$diskF - Used:$usedF - Free:$freeF - Used Space: $perc%|Used=$perc;$strWarning;$strCritical;0;100"

	if [ $perc -ge $strCritical ]; then
		echo "CRITICAL: $OUTPUT"
		exit 2
	elif [ $perc -ge $strWarning ]; then
		echo "WARNING: $OUTPUT"
		exit 1
	else
		echo "OK: $OUTPUT"
		exit 0
	fi

# CPU ----------------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "cpu" ]; then
	CPU="$(_snmpgetval 1.3.6.1.4.1.24681.1.2.1.0 | sed -E 's/"([0-9.]+) ?%"/\1/')"

	OUTPUT="CPU Load=$CPU%|CPU load=$CPU%;$strWarning;$strCritical;0;100"

	if (( $(echo "$CPU > $strCritical" | bc -l) )); then
		echo "CRITICAL: $OUTPUT"
		exit 2
	elif ((  $(echo "$CPU > $strWarning" | bc -l) )); then
		echo "WARNING: $OUTPUT"
		exit 1
	else
		echo "OK: $OUTPUT"
		exit 0
	fi

# CPUTEMP ----------------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "cputemp" ]; then
	TEMP0="$(_snmpgetval .1.3.6.1.4.1.24681.1.2.5.0 | sed -E 's/"([0-9.]+) ?C.*/\1/')"
	OUTPUT="CPU Temperature=${TEMP0}C|NAS CPUtemperature=${TEMP0}C;$strWarning;$strCritical;0;90"

	if [ "$TEMP0" -ge 89 ]; then
		echo "CPU temperature too high!: $OUTPUT"
		exit 3
	else
		if [ "$TEMP0" -ge "$strCritical" ]; then
			echo "CRITICAL: $OUTPUT"
			exit 2
		fi
		if [ "$TEMP0" -ge "$strWarning" ]; then
			echo "WARNING: $OUTPUT"
			exit 1
		fi
		echo "OK: $OUTPUT"
		exit 0
	fi

# Free RAM---------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "freeram" ]; then
	totalMemStr="$(_snmpgetval 1.3.6.1.4.1.24681.1.2.2.0)"
	freeMemStr="$(_snmpgetval 1.3.6.1.4.1.24681.1.2.3.0)"

	totalMemSize="$(echo "$totalMemStr" | sed -E 's/"([0-9.]+) ?.?B"/\1/')"
	freeMemSize="$(echo "$freeMemStr" | sed -E 's/"([0-9.]+) ?.?B"/\1/')"
	totalMemUnit="$(echo "$totalMemStr" | sed -E 's/"[0-9.]+ ?(.?B)"/\1/')"
	freeMemUnit="$(echo "$freeMemStr" | sed -E 's/"[0-9.]+ ?(.?B)"/\1/')"

	totalMemExp="$(_get_exp "$totalMemUnit")"
	freeMemExp="$(_get_exp "$freeMemUnit")"

	totalMem="$(echo "scale=0; $totalMemSize*(2^$totalMemExp)" | bc -l)"
	freeMem="$(echo "scale=0; $freeMemSize*(2^$freeMemExp)" | bc -l)"

	usedMem="$(echo "scale=0; $totalMem-$freeMem" | bc -l)"
	percMem="$(echo "scale=0; $usedMem*100/$totalMem" | bc -l)"

	totalMemH="$(echo "scale=1; $totalMem/(2^$totalMemExp)" | bc -l)"
	freeMemH="$(echo "scale=1; $freeMem/(2^$freeMemExp)" | bc -l)"
	usedMemH="$(echo "scale=1; $usedMem/(2^$freeMemExp)" | bc -l)"

	totalMemF="$totalMemH$totalMemUnit"
	freeMemF="$freeMemH$freeMemUnit"
	usedMemF="$usedMemH$freeMemUnit"

	OUTPUT="Total:$totalMemF - Used:$usedMemF - Free:$freeMemF = $percMem%|Memory usage=$percMem%;$strWarning;$strCritical;0;100"

	if [ $percMem -ge $strCritical ]; then
		echo "CRITICAL: $OUTPUT"
		exit 2
	elif [ $percMem -ge $strWarning ]; then
		echo "WARNING: $OUTPUT"
		exit 1
	else
		echo "OK: $OUTPUT"
		exit 0
	fi

# System Temperature---------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "temp" ]; then
	TEMP0="$(_snmpgetval .1.3.6.1.4.1.24681.1.2.6.0 | sed -E 's/"([0-9.]+) ?C.*/\1/')"
	OUTPUT="Temperature=${TEMP0}C|NAS temperature=${TEMP0}C;$strWarning;$strCritical;0;80"

	if [ "$TEMP0" -ge 89 ]; then
		echo "System temperature too high!: $OUTPUT"
		exit 3
	else
		if [ "$TEMP0" -ge "$strCritical" ]; then
			echo "CRITICAL: $OUTPUT"
			exit 2
		fi
		if [ "$TEMP0" -ge "$strWarning" ]; then
			echo "WARNING: $OUTPUT"
			exit 1
		fi
		echo "OK: $OUTPUT"
		exit 0
	fi

# HD# Temperature---------------------------------------------------------------------------------------------------------------------------------------
elif [[ "$strpart" == hd?temp ]]; then
	hdnum="$(echo "$strpart" | sed -E 's/hd([0-9]+)temp/\1/')"
	TEMPHD="$(_snmpgetval "1.3.6.1.4.1.24681.1.2.11.1.3.$hdnum" | sed -E 's/"([0-9.]+) ?C.*/\1/')"
	OUTPUT="Temperature=${TEMPHD}C|HDD$hdnum temperature=${TEMPHD}C;$strWarning;$strCritical;0;60"

	if [ "$(echo "$TEMPHD" | sed -E 's/[0-9.]+//g')" != "" ]; then
		echo "ERROR: $TEMPHD"
		exit 4
	fi
	if [ "$TEMPHD" -ge "59" ]; then
		echo "HDD$hdnum temperature too high!: $OUTPUT"
		exit 3
	else
		if [ "$TEMPHD" -ge "$strCritical" ]; then
			echo "CRITICAL: $OUTPUT"
			exit 2
		fi
		if [ "$TEMPHD" -ge "$strWarning" ]; then
			echo "WARNING: $OUTPUT"
			exit 1
		fi
		echo "OK: $OUTPUT"
		exit 0
	fi

# Volume # Status----------------------------------------------------------------------------------------------------------------------------------------
elif [[ "$strpart" == vol?status ]]; then
	volnum="$(echo "$strpart" | sed -E 's/vol([0-9]+)status/\1/')"
	Vol_Status="$(_snmpgetval "1.3.6.1.4.1.24681.1.2.17.1.6.$volnum" | sed 's/^"\(.*\).$/\1/')"

	if [[ "$Vol_Status" == 'No Such Instance'* ]]; then
		echo "ERROR: $Vol_Status"
		exit 4
	elif [ "$Vol_Status" == "Ready" ]; then
		echo "OK: $Vol_Status"
		exit 0
	elif [ "$Vol_Status" == "Rebuilding..." ]; then
		echo "WARNING: $Vol_Status"
		exit 1
	else
		echo "CRITICAL: $Vol_Status"
		exit 2
	fi

# HD# Status----------------------------------------------------------------------------------------------------------------------------------------
elif [[ "$strpart" == hd?status ]]; then
	hdnum="$(echo "$strpart" | sed -E 's/hd([0-9]+)status/\1/')"
	HDstat="$(_snmpgetval "1.3.6.1.4.1.24681.1.2.11.1.7.$hdnum" | sed 's/^"\(.*\).$/\1/')"

	if [[ "$HDstat" == 'No Such Instance'* ]]; then
		echo "ERROR: $HDstat"
		exit 4
	elif [ "$HDstat" == "GOOD" ]; then
		echo "OK: GOOD"
		exit 0
	else
		echo "CRITICAL: ERROR"
		exit 2
	fi

# HD Status----------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "hdstatus" ]; then
	hdnum="$(_snmpgetval .1.3.6.1.4.1.24681.1.2.10.0)"
	hdok=0
	hdnop=0
	output_crit=""

	for (( c=1; c<=$hdnum; c++ ))
	do
		HD="$(_snmpgetval "1.3.6.1.4.1.24681.1.2.11.1.7.$c" | sed 's/^"\(.*\).$/\1/')"

		if [ "$HD" == "GOOD" ]; then
			((hdok+=1))
		elif [ "$HD" == "--" ]; then
			((hdnop+=1))
		else
			output_crit="${output_crit} Disk ${c}"
		fi
	done

	if [ -n "$output_crit" ]
	then
		echo "CRITICAL: ${output_crit}"
		exit 2
	else
		echo "OK: Online Disk $hdok, Free Slot $hdnop"
		exit 0
	fi

# Volume Status----------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "volstatus" ]; then
     ALLOUTPUT=""
     PERFOUTPUT=""
     WARNING=0
     CRITICAL=0
     VOL=1
     VOLCOUNT=$(_snmpget .1.3.6.1.4.1.24681.1.2.16.0 | awk '{print $4}')

     while [ "$VOL" -le "$VOLCOUNT" ]; do
        Vol_Status=$(_snmpget .1.3.6.1.4.1.24681.1.2.17.1.6.$VOL | awk '{print $4}' | sed 's/^"\(.*\).$/\1/')

        if [ "$Vol_Status" == "Ready" ]; then
                VOLSTAT="OK: $Vol_Status"

        elif [ "$Vol_Status" == "Rebuilding..." ]; then
                VOLSTAT="WARNING: $Vol_Status"
                WARNING=1
        else
                VOLSTAT="CRITICAL: $Vol_Status"
                CRITICAL=1
        fi

        VOLCAPACITY=0
        VOLFREESIZE=0
        VOLPCT=0

        VOLCAPACITY=$(_snmpget .1.3.6.1.4.1.24681.1.2.17.1.4.$VOL | awk '{print $4}' | sed 's/^"\(.*\).$/\1/')
        VOLFREESIZE=$(_snmpget .1.3.6.1.4.1.24681.1.2.17.1.5.$VOL | awk '{print $4}' | sed 's/^"\(.*\).$/\1/')
        UNITtest=$(_snmpget 1.3.6.1.4.1.24681.1.2.17.1.4.$VOL | awk '{print $5}' | sed 's/.*\(.B\).*/\1/')
	UNITtest2=$(_snmpget 1.3.6.1.4.1.24681.1.2.17.1.5.$VOL | awk '{print $5}' | sed 's/.*\(.B\).*/\1/')

	if [ "$UNITtest" == "TB" ]; then
	 factor=$(echo "scale=0; 1000" | bc -l)
	elif [ "$UNITtest" == "GB" ]; then
	 factor=$(echo "scale=0; 100" | bc -l)
	else
	 factor=$(echo "scale=0; 1" | bc -l)
	fi

	if [ "$UNITtest2" == "TB" ]; then
	 factor2=$(echo "scale=0; 1000" | bc -l)
	elif [ "$UNITtest2" == "GB" ]; then
	 factor2=$(echo "scale=0; 100" | bc -l)
	else
	 factor2=$(echo "scale=0; 1" | bc -l)
	fi

	VOLCAPACITYF=$(echo "scale=0; $VOLCAPACITY*$factor" | bc -l)
	VOLFREESIZEF=$(echo "scale=0; $VOLFREESIZE*$factor2" | bc -l)

        VOLPCT=`echo "($VOLFREESIZEF*100)/$VOLCAPACITYF" | bc`

        if [ "$VOLPCT" -le "$strCritical" ]; then
                VOLPCT="CRITICAL: $VOLPCT"
                CRITICAL=1
        elif [ "$VOLPCT" -le "$strWarning" ]; then
                VOLPCT="WARNING: $VOLPCT"
                WARNING=1
        fi

        if [ "$VOL" -lt "$VOLCOUNT" ]; then
           ALLOUTPUT="${ALLOUTPUT}Volume #${VOL}: $VOLSTAT, Total Size (bytes): $VOLCAPACITY $UNITtest, Free: $VOLFREESIZE $UNITtest2 (${VOLPCT}%), "
        else
           ALLOUTPUT="${ALLOUTPUT}Volume #${VOL}: $VOLSTAT, Total Size (bytes): $VOLCAPACITY $UNITtest, Free: $VOLFREESIZE $UNITtest2 (${VOLPCT}%)"
        fi

	#Performance Data
        if [ $VOL -gt 1 ]; then
          PERFOUTPUT=$PERFOUTPUT" "
        fi
        PERFOUTPUT=$PERFOUTPUT"FreeSize_Volume-$VOL=${VOLPCT}%;$strWarning;$strCritical;0;100"

        VOL=`expr $VOL + 1`
     done

     echo $ALLOUTPUT"|"$PERFOUTPUT

     if [ $CRITICAL -eq 1 ]; then
        exit 2
     elif [ $WARNING -eq 1 ]; then
        exit 1
     else
        exit 0
     fi

# Power Supply Status  ----------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "powerstatus" ]; then
	ALLOUTPUT=""
	WARNING=0
	CRITICAL=0
	PS=1
	COUNT="$(_snmpgetval .1.3.6.1.4.1.24681.1.4.1.1.1.1.3.1.0)"

	if [[ "$COUNT" == 'No Such Object'* ]]; then
		echo "ERROR: $COUNT"
		exit 4
	fi

	while [ "$PS" -le "$COUNT" ]; do
		STATUS="$(_snmpgetval ".1.3.6.1.4.1.24681.1.4.1.1.1.1.3.2.1.4.$PS")"
		if [ "$STATUS" -eq 0 ]; then
			PSSTATUS="OK: GOOD"
		else
			PSSTATUS="CRITICAL: ERROR"
			CRITICAL=1
		fi
		ALLOUTPUT="${ALLOUTPUT}Power Supply #$PS - $PSSTATUS"
		if [ "$PS" -lt "$COUNT" ]; then
			ALLOUTPUT="$ALLOUTPUT\n"
		fi
		PS="`expr $PS + 1`"
	done

	echo "$ALLOUTPUT"

	if [ $CRITICAL -eq 1 ]; then
		exit 2
	elif [ $WARNING -eq 1 ]; then
		exit 1
	else
		exit 0
	fi

# Fan Status----------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "fans" ]; then
	ALLOUTPUT=""
	PERFOUTPUT=""
	WARNING=0
	CRITICAL=0
	FAN=1
	FANCOUNT="$(_snmpgetval .1.3.6.1.4.1.24681.1.2.14.0)"

	while [ "$FAN" -le "$FANCOUNT" ]; do
		FANSPEED="$(_snmpgetval ".1.3.6.1.4.1.24681.1.2.15.1.3.$FAN" | sed -E 's/"([0-9]+) ?RPM"/\1/')"

		#Performance data
		if [ $FAN -gt 1 ]; then
			PERFOUTPUT="$PERFOUTPUT "
		fi
		PERFOUTPUT="${PERFOUTPUT}Fan-$FAN=$FANSPEED;$strWarning;$strCritical"

		if [ "$FANSPEED" == "" ]; then
			FANSTAT="CRITICAL: $FANSPEED RPM"
			CRITICAL=1
		elif [ "$FANSPEED" -le "$strCritical" ]; then
			FANSTAT="CRITICAL: $FANSPEED RPM"
			CRITICAL=1
		elif [ "$FANSPEED" -le "$strWarning" ]; then
			FANSTAT="WARNING: $FANSPEED RPM"
			WARNING=1
		else
			FANSTAT="OK: $FANSPEED RPM"
		fi

		ALLOUTPUT="${ALLOUTPUT}Fan #${FAN}: $FANSTAT"
		if [ "$FAN" -lt "$FANCOUNT" ]; then
			ALLOUTPUT="${ALLOUTPUT}, "
		fi
		FAN="`expr $FAN + 1`"
	done

	echo "$ALLOUTPUT|$PERFOUTPUT"

	if [ $CRITICAL -eq 1 ]; then
		exit 2
	elif [ $WARNING -eq 1 ]; then
		exit 1
	else
		exit 0
	fi

# System Uptime----------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "systemuptime" ]; then
	netuptime="$(_snmpget .1.3.6.1.2.1.1.3.0 | awk '{print $5, $6, $7, $8}')"
	sysuptime="$(_snmpget .1.3.6.1.2.1.25.1.1.0 | awk '{print $5, $6, $7, $8}')"

	echo "System Uptime $sysuptime - Network Uptime $netuptime"
	exit 0

# System Info------------------------------------------------------------------------------------------------------------------------------------------
elif [ "$strpart" == "sysinfo" ]; then
	model="$(_snmpgetval .1.3.6.1.4.1.24681.1.2.12.0 | sed 's/^"\(.*\).$/\1/')"
	hdnum="$(_snmpgetval .1.3.6.1.4.1.24681.1.2.10.0)"
	VOLCOUNT="$(_snmpgetval .1.3.6.1.4.1.24681.1.2.16.0)"
	name="$(_snmpgetval .1.3.6.1.4.1.24681.1.2.13.0 | sed 's/^"\(.*\)$/\1/')"
	firmware="$(_snmpgetval .1.3.6.1.2.1.47.1.1.1.1.9.1 | sed 's/^"\(.*\)$/\1/')"

	echo "NAS $name, Model $model, Firmware $firmware, Max HD number $hdnum, No. Volume $VOLCOUNT"
	exit 0

#----------------------------------------------------------------------------------------------------------------------------------------------------
else
	echo -e "\nUnknown Part!" && exit 3
fi
exit 0
