#!/bin/bash
#
# Modifying A9K PEs to use multipath Round-Robin
#
#hostlist=(tile1 tile2 tile3 tile4 tile5 tile6 tile7 tile8 tile9 til10 tile11 tile12 tile13 tile14 tile15 tile16 tile17 tile18 tile19 tile20)
hostlist=(tile1 tile2 tile3 tile4 tile5 tile6 tile7 tile8 tile9)
#hostlist=(tile1)

# this is true for Isolated network only	
for host in "${hostlist[@]}";do
	host_ip=`ssh -t perf-proxy ssh perf-util cat /etc/dhcp/dhcpd.conf |grep -w $host|awk -F " |;" '{print $9}'`
	ssh perf-proxy ping -c1 $host_ip > /dev/null
	if [[ $? -ne 0 ]];then
	   echo "[ERROR] No netwrok connectivity to host $host, ping failed. Existing"
	   exit 1
	fi
	echo "[INFO] Start - Setting host $host multipath and queue depth"
	for dev in `ssh perf-proxy ssh $host_ip esxcli storage core device list |grep ^"naa."`;do
		dev_pe=`ssh perf-proxy ssh $host_ip esxcli storage core device list -d $dev|grep "PE"|awk '{print $4}'`
		dev_model=`ssh perf-proxy ssh $host_ip esxcli storage core device list -d $dev|grep "2810"|awk '{print $2}'`
		if [[ "$dev_pe" = "true" ]] || [[ "$dev_model" = "2810XIV" ]];then
			echo $dev
		#if ( `ssh perf-proxy ssh $host_ip esxcli storage core device list -d $dev|grep "PE"|awk '{print $4}'` -eq "true" );then
			#echo $dev_pe $dev_model
			#ssh perf-proxy ssh $host_ip "esxcli storage nmp device set -d $dev -P VMW_PSP_RR"
			# setting the round robin policy to switch path after every IO, increases performance 
			ssh perf-proxy ssh $host_ip "esxcli storage nmp psp roundrobin deviceconfig set -d $dev --type=iops --iops=1"
			# increasing the PE max queue depth to 64 which is equal to the HBA setting
			hba_max_qd=`ssh perf-proxy ssh $host_ip esxcli storage core device list -d $dev|grep Max|awk -F":" '{print $2}'|sed 's/ //g'`
			pe_max_qd=`ssh perf-proxy ssh $host_ip esxcli storage core device list -d $dev|grep IOs|awk -F":" '{print $2}'|sed 's/ //g'`
			if [[ $hba_max_qd -gt $pe_max_qd ]]; then
				ssh perf-proxy ssh $host_ip "esxcli storage core device set -O $hba_max_qd -d $dev"
			fi
			ssh perf-proxy ssh $host_ip esxcli storage nmp device list -d $dev|grep "policy"
			ssh perf-proxy ssh $host_ip esxcli storage core device list -d $dev|grep "Max\|IOs"
		fi	
	done
	echo "[INFO] End - Setting host $host multipath and queue depth"
done