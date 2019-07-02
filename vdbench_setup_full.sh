#!/bin/bash
#
# This script gets as input: system_name, active dataset and volume number. 
# This script has internal definitions of host_list, protocol, system clean, system setup.
# Then it creates basic vdbench output
#
#
# General Script Setup
to_clean_system="no"
to_do_fccon="no"
to_setup_system="yes"
to_create_vdbench="yes"
is_it_iSCSI="no"
is_it_vlan="no"
is_it_nvme="no"
system_name="ba-46"
active_dataset=315000
vol_number=240
pool_name="pool_group10"
hostlist=(rmhost4 rmhost5 rmhost6 rmhost7 rmhost8 rmhost9)
#hostlist=(rmhost4 rmhost5 rmhost6 rmhost7 rmhost8 rmhost9 mc005 mc062 mc063 fusionbr)
#hostlist=(rmhost1 rmhost2 rmhost3)
#host_list='mc028 mc029 mc031 mc032 mc034 mc035 mc036 mc051 mc052 mc069'

function system_clean {
echo "[INFO] Start - system $system_name cleanup"
echo "[INFO] Start - vol unmap, delete and pool deletion"
vol_clean_list=`ssh $system_name xcli.py vol_list pool=$pool_name -z|awk '{print$1}'`
#vol_clean_list=`ssh $system_name xcli.py -z mapping_list|awk -F " " '{print $2}'`
for vol_clean in $vol_clean_list;do
	unmap_host=`ssh $system_name xcli.py vol_mapping_list vol=$vol_clean -z | awk '{print $1}'`
	ssh $system_name xcli.py unmap_vol vol=$vol_clean host=$unmap_host -y 1> /dev/null
	ssh $system_name xcli.py cg_remove_vol -y vol=$vol_clean 1> /dev/null
	ssh $system_name xcli.py vol_delete -y vol=$vol_clean 1> /dev/null
done
echo "[INFO] End - vol unmap, delete and pool deletion"
echo "[INFO] Start - cg and pool deletion"
ssh $system_name xcli.py cg_delete cg=cg_$pool_name 1> /dev/null
ssh $system_name xcli.py pool_delete -y pool=$pool_name 1> /dev/null
echo "[INFO] End - cg and pool deletion"
#
### full clean procedure
#pool_list=`ssh $system_name xcli.py -z pool_list|cut -f1 -d" "`
#for pool in $pool_list;do
#   vol_list=`ssh $system_name xcli.py -z vol_list pool=$pool |cut -f1 -d" "`
#   for vol in $vol_list;do
##      ssh $system_name xcli.py unmap_vol -y vol=$vol
#      ssh $system_name xcli.py cg_remove_vol -y vol=$vol 1> /dev/null
#      ssh $system_name xcli.py vol_delete -y vol=$vol 1> /dev/null
#   done
#   ssh $system_name xcli.py pool_delete -y pool=$pool 1> /dev/null
#done
#
echo "[INFO] Start - host cleaning"
for host in "${hostlist[@]}";do
	echo $host
    ssh $system_name xcli.py host_delete host=$host -y 1> /dev/null
	host_dev_list=`ssh $host multipath -ll|grep "failed"|awk '{print $2}'`
	for dev in $host_dev_list;do
		ssh $host "echo 1 > /sys/class/scsi_device/$dev/device/delete"
	done
	host_fc_lip=`ssh $host ls /sys/class/fc_host/`
	for lip in $host_fc_lip;do
		ssh $host "echo '1' > /sys/class/fc_host/$lip/issue_lip"
	done
	ssh $host service multipathd restart > /dev/null
#	ssh $host rescan-scsi-bus.sh -f -r > /dev/null
#	ssh $host multipath -F > /dev/null
done
echo "[INFO] End - host cleaning"
echo "[INFO] End - system $system_name cleanup"
#
}

function fccon {
echo "[INFO] Start - deleting all exiting zones for ${system_name}"
echo "[INFO] End - deleting all exiting zones for ${system_name}"
echo "[INFO] Start - creating new zones for ${system_name}"
# creating host list for stcon
fccon_hosts=""
for host in "${hostlist[@]}";do 
	fccon_hosts="${fccon_hosts} -host ${host}"
	echo $fccon_hosts
done
ssh stcon "/opt/FCCon/fcconnect.pl -op DisConnect -stor ${system_name} ${fccon_hosts}"
ssh stcon "/opt/FCCon/fcconnect.pl -op Connect -stor ${system_name} ${fccon_hosts}"
echo "[INFO] End - creating new zones for ${system_name}"
}

function system_setup {
#@@@@
vol_clean_list=`ssh $system_name xcli.py -z mapping_list|awk -F " " '{print $2}'`
for vol_clean in $vol_clean_list;do
	unmap_host=`ssh $system_name xcli.py vol_mapping_list vol=$vol_clean -z | awk '{print $1}'`
	ssh $system_name xcli.py unmap_vol vol=$vol_clean host=$unmap_host -y 1> /dev/null
done
#@@@@
#
echo "[INFO] Start system $system_name $interface setup"
if [ "$interface" == "iscsi" ]; then
	if [ "$is_it_vlan" == "yes" ]; then
		echo "[INFO] Requested iSCSI is VLAN Tagging"
	else 
		ssh $system_name /local/scratch/$system_name"_iscsi.sh"
		target_subnet1_ip=`ssh $system_name xcli.py ipinterface_list |grep -m 1 -i 172.18.5 |awk -F " " '{print $6}'`
		target_subnet2_ip=`ssh $system_name xcli.py ipinterface_list |grep -m 1 -i 172.18.6 |awk -F " " '{print $6}'`
		# get A9K IQN
		a9k_iqn=`ssh $system_name xcli.py config_get |grep iscsi_name|awk -F " " '{print $2}'`	
	fi
	echo "$system_name iSCSI interfaces:"
	ssh $system_name xcli.py ipinterface_list | grep -i iscsi
elif [ $is_it_nvme == "yes" ]; then
	echo "[INFO] Requested FC configuration is NVMe"
	echo "[INFO] Verifying FC cards on all modules for system $system_name to support NVMe"
	for module in `ssh $system_name xcli.py module_list -z|awk '{print $1}'|awk -F":" '{print $3}'`;do
		for fc in `ssh $system_name ssh module-$module lspci -n | grep 1077|awk '{print $3}'|awk -F':' '{print $2}'`;do
			if [ $fc != "2261" ]; then
				echo "[WARM] FC on module $module on system $system_name is $fc. It does not support NVMe"
				exit 1
			fi
		done
	done
	echo "[INFO] Verifying FC cards firmware on system $system_name to support NVMe"
	for fc_fw in `ssh $system_name xcli.py fc_port_list -x |grep "active_firmware"|awk -F'"' '{print $2}'`;do
		if [ $fc_fw != "8:9:1" ]; then
				echo "[WARM] FC firmware on system $system_name is $fc_fw. It does not support NVMe"
				exit 1
		fi
	done
	echo "[INFO] FC on system $system_name supports NVMe"
	echo "[INFO] Configuring all FC cards protocol on system $system_name to be NVMe"	
	for fc_port in `ssh $system_name xcli.py fc_port_list -z|awk '{print $1}'`;do 
		ssh $system_name xcli.py fc_port_config fc_port=$fc_port protocol=NVMe 1>/dev/null
	done
	echo "[INFO] system $system_name FC NVMe ports:"
	ssh $system_name xcli.py fc_port_list -f component_id,protocol
fi

echo "[INFO] Start - pool creation"
pool_size=`echo "$active_dataset/0.95"|bc`
ssh $system_name xcli.py pool_create pool=$pool_name size=$pool_size snapshot_size=0 -y 1>/dev/null
echo "[INFO] End - pool creation"
#
echo "[INFO] Start - cg creation"
ssh $system_name xcli.py cg_create pool=$pool_name cg=cg_$pool_name 1>/dev/null
echo "[INFO] End - cg creation"
#
echo "[INFO] Start - volume creation and adding to cg"
for vol in $(seq 1 $vol_number);do
   ssh $system_name xcli.py vol_create pool=$pool_name size=$vol_size vol=perf_${pool_name}_${vol} 1>/dev/null
   ssh $system_name xcli.py cg_add_vol vol=perf_${pool_name}_${vol} cg=cg_$pool_name 1>/dev/null 
done
echo "[INFO] End - volume creation and adding to cg"
#
for host in "${hostlist[@]}";do
	echo "[INFO] Start - host definition $host using $interface"
	ssh $system_name xcli.py host_define host=$host 1>/dev/null
	if [ "$interface" == "iscsi" ]; then
		host_iqn=`ssh $host cat /etc/iscsi/initiatorname.iscsi|cut -d "=" -f2`
		# Adding hosts iqn on A9K system
		ssh $system_name xcli.py host_add_port host=$host iscsi_name=$host_iqn > /dev/null
		# command to verify connectivity 
		ssh $host ping -c1 $target_subnet1_ip > /dev/null
		if [[ $? -ne 0 ]]; then
		   echo "no iscsi connectivity on host $host subnet $target_subnet1_ip"
		   exit
		fi
		ssh $host ping -c1 $target_subnet2_ip > /dev/null
		if [[ $? -ne 0 ]]; then
		   echo "no iscsi connectivity on host $host subnet $target_subnet2_ip"
		   exit
		fi
		echo "iscsi connectivity is OK on host $host for both subnets"
		#
		# command to verify mtu=9000, jambo frames
		ssh $host traceroute -m 1 -4 --mtu $target_subnet1_ip|grep -E "$target_subnet1_ip.*9000" > /dev/null
		if [[ $? -ne 0 ]]; then
		   echo "MTU is not 9000 on host $host subnet $target_subnet1_ip"
		   exit 
		fi
		ssh $host traceroute -m 1 -4 --mtu $target_subnet2_ip|grep -E "$target_subnet2_ip.*9000" > /dev/null
		if [[ $? -ne 0 ]]; then
		   echo "MTU is not 9000 on host $host subnet $target_subnet2_ip"
		   exit 
		fi
		echo "MTU 9000 is OK on host $host for both subnets"

		#
		# checking if iscsi service is running
		ssh $host systemctl status iscsid.service |grep running > /dev/null
		if [[ $? -ne 0 ]]; then
		   echo "iscsid service is down on host $host"
		   exit
		fi
		echo "iscsid service is OK on host $host"
		# Cleaning iSCSI
		echo "Start - Cleaning host $host iSCSI and luns"
		for i in `ssh $host iscsiadm -m node|sed 's/ /,/g'`;do
		   portal=`echo $i |cut -f1 -d","`
		   target_iqn=`echo $i|cut -f3 -d","`
		   ssh $host iscsiadm -m node -u -T $target_iqn -p $portal
		   ssh $host iscsiadm -m node -o delete -T $target_iqn -p $portal
		done
		for i in `ssh $host iscsiadm -m discovery`;do
		   discovery=`echo $i |cut -f1 -d" "`
		   ssh $host iscsiadm -m discoverydb -t sendtargets -o delete -p $discovery
		done
		echo "End - Cleaning host $host iSCSI and luns"
		#
		#start_count=`echo $(($start_count+$host_mapping))` 
		#end_count=`echo $(($end_count+$host_mapping))` 
		echo "Start -  Connecting host $host to iSCSI and luns"
		# discover the A9K target ips
		ssh $host iscsiadm -m discovery -t st -p $target_subnet1_ip 
		#OR iscsiadm --mode discovery -t sendtargets --portal 172.18.5.36
		# Login to the A9K discovered targets
		ssh $host iscsiadm -m node -l -n $a9k_iqn
		#
		ssh $host service multipathd stop
		sleep 5
		ssh $host rescan-scsi-bus.sh -r -f > /dev/null
		ssh $host service multipathd start
		sleep 5
		ssh $host multipath -F > /dev/null
		ssh $host multipath > /dev/null
		echo "End -  Connecting host $host to iSCSI and luns"
	else
		host_fc_wwpn=`ssh $host cat /sys/class/fc_host/host*/port_name|cut -f2 -d "x"`
		for fc_wwpn in $host_fc_wwpn;do
		# Adding hosts wwpn on A9K system
			echo $fc_wwpn
			ssh $system_name xcli.py host_add_port host=$host fcaddress=$fc_wwpn 1>/dev/null
		done
		if [ $is_it_nvme == "yes" ];then
			echo "[INFO] Requested FC protocol is NVMe, verifying and configuring host $host to support NVMe"
			echo "[INFO] Verifying host $host FC firmware to support NVMe"
			for host_fc_fw in `ssh $host qaucli -i |grep "Running Firmware Version"|awk '{print $5}'`;do
				if [ $host_fc_fw != "8.09.01" ]; then
					echo "[WARN] FC firmware $host_fc_fw on host $host does not support NVMe"
					exit 1
				fi
			done
			echo "[INFO] Verifying host $host FC driver to support NVMe"
			for host_fc_driver in `ssh $host qaucli -i |grep "Driver"|awk '{print $4}'|awk '{print $1}'`;do
				if [ $host_fc_driver != "10.01.00.23.15.0-k1" ]; then
					echo "[WARN] FC driver $host_fc_driver on host $host does not support NVMe"
					exit 1
				fi
			done
			echo "[INFO] stopping multipath on host $host"
			ssh $host service multipathd stop
		else
			host_dev_list=`ssh $host multipath -ll|grep "failed"|awk '{print $2}'`
			for dev in $host_dev_list;do
				ssh $host "echo 1 > /sys/class/scsi_device/$dev/device/delete"
			done
			host_fc_lip=`ssh $host ls /sys/class/fc_host/`
			for lip in $host_fc_lip;do
				ssh $host "echo '1' > /sys/class/fc_host/$lip/issue_lip"
			done
			ssh $host service multipathd restart > /dev/null
			echo "[INFO] End - host cleaning on $host"
		fi
	fi
	echo "[INFO] End - host definition $host using $interface"
#    for vol in $(seq $start_count $end_count);do
	echo "[INFO] Start - volume mapping host $host"
	for lunid in $(seq 1 $host_mapping);do
	   ssh $system_name xcli.py map_vol host=$host lun=$lunid vol=perf_${pool_name}_${vol_map} 1>/dev/null
	   ((vol_map++))
	done
	echo "[INFO] End - volume mapping host $host"
	#
	if [ $is_it_nvme == "yes" ];then
		#ssh $host modprobe -r qla2xxx
		sleep 5
		#ssh $host modprobe qla2xxx
	else
		ssh $host rescan-scsi-bus.sh > /dev/null
	fi
#	ssh $host multipath -F > /dev/null
echo "[INFO] End system $system_name $interface setup"
done
}

function indexof {
i=0;
while [ "$i" -lt "${#hostlist[@]}" ] && [ "${hostlist[$i]}" != "$1" ]; do
	((i++));
done;
echo $i;
#return $i
}
#
### main ###
#@if [ $# != 4 ];then
#@	echo "sample: $0 system_name active_dataset_size_GB vol_number pool_name"
#@	exit
#@fi
#@system_name=$1
#@active_dataset=$2
#@vol_number=$3
#@pool_name=$4
#interface=`echo $4|awk '{print tolower($1)}'`

#@echo "Script input parms are: "$@
#@echo "Script internal parms are:"
echo -e "to_clean_system:\t"$to_clean_system
echo -e "to_do_fccon:\t\t"$to_do_fccon
echo -e "to_setup_system:\t"$to_setup_system
echo -e "to_create_vdbench:\t"$to_create_vdbench
echo -e "is_it_iSCSI:\t\t"$is_it_iSCSI
echo -e "is_it_nvme:\t\t"$is_it_nvme
echo -e "host list:\t\t"${hostlist[@]}
echo -e "system name:\t\t"$system_name
echo -e "active dataset size:\t"$active_dataset
echo -e "number of volumes::\t"$vol_number
echo -e "pool nameis:\t\t"$pool_name
echo -e "press enter to continue"
read nu

#
vol_size=`echo "$active_dataset/$vol_number"|bc`
host_number=`echo ${#hostlist[@]}`
host_mapping=`echo "$vol_number/$host_number"|bc`
start_count=1
end_count=$host_mapping
vol_map=1

if [ $is_it_iSCSI == "yes" ];then
	echo "[INFO] Requested protocol is iSCSI"
	interface="iscsi"
else
	echo "[INFO] Requested protocol is FC"
	interface="fc"
fi
#
if [ $to_clean_system == "yes" ];then
	echo "[INFO] Running system cleaning"
	system_clean
else
	echo "[INFO] Not running system cleaning"
fi
#
if [ $to_do_fccon == "yes" ];then
	echo "[INFO] Running FCCon setup"
	fccon
else
	echo "[INFO] Not running FCCon setup"
fi
#
if [ $to_setup_system == "yes" ];then
	echo "[INFO] Running system setup"
	system_setup
else
	echo "[INFO] Not running system setup"
fi
#exit
#
if [ $to_create_vdbench == "yes" ];then
	echo "[INFO] Running vdbench config creation"
	sd=0
	vdbench_vol_size=`echo "$vol_size/1.1"|bc`
	vdbench_sd_output="${system_name}_${interface}_${active_dataset}GB_vdbench_config_${pool_name}"
	rm -f /home/vdbench/$vdbench_sd_output
#	echo "compratio=2.86" > /home/vdbench/$vdbench_sd_output
	echo "compratio=3" > /home/vdbench/$vdbench_sd_output
	echo "dedupratio=2,dedupunit=256k,dedupsets=5%" >> /home/vdbench/$vdbench_sd_output
	echo "debug=25" >> /home/vdbench/$vdbench_sd_output
	echo "hd=default,vdbench=/root/vdbench/bin,user=root,shell=ssh" >> /home/vdbench/$vdbench_sd_output
	for host in "${hostlist[@]}";do 
		hd=$( indexof $host )
		echo "hd=hd$hd,system=$host" >> /home/vdbench/$vdbench_sd_output
	done
	#
	system_serial=`ssh $system_name xcli.py config_get |grep system_id |awk '{print $2}'`
	system_serial_hex=`echo "obase=16; $system_serial"|bc`
	if [ $is_it_nvme == "yes" ];then
		for host in "${hostlist[@]}";do 
			echo "$host"
			ssh $host "service multipathd stop" > /dev/null
			#ssh $host modprobe -r qla2xxx
			#sleep 5
			#ssh $host modprobe qla2xxx
			#sleep 15
			hd=$( indexof $host )
			for nvme_dev in `ssh $host nvme list |grep -i $system_serial | awk '{print $1}'`;do  
				echo "sd=sd$sd,host=hd$hd,lun=$nvme_dev,openflags=(o_direct,o_sync,fsync),size=$vdbench_vol_size""g,threads=10,hitarea=170m" >> /home/vdbench/$vdbench_sd_output
				((sd++))
			done
		done
	else
		for host in "${hostlist[@]}";do 
			echo "$host"
			ssh $host "service multipathd stop" > /dev/null
			sleep 5
			ssh $host "rescan-scsi-bus.sh -r -f" > /dev/null
			ssh $host "service multipathd start" > /dev/null
			sleep 5
#			ssh $host "rescan-scsi-bus.sh" > /dev/null
			ssh $host "multipath -F" > /dev/null
			ssh $host "multipath" > /dev/null
			hd=$( indexof $host )
			for dm in `ssh $host multipath -ll |grep -i $system_serial_hex |cut -f2 -d"-"|cut -f1 -d" "|sort -n`;do  
				echo "sd=sd$sd,host=hd$hd,lun=/dev/dm-$dm,openflags=(o_direct,o_sync,fsync),size=$vdbench_vol_size""g,threads=10,hitarea=170m" >> /home/vdbench/$vdbench_sd_output
				((sd++))
			done
		done
	fi
	echo "rd=prealloc,sd=*,elapsed=1000h,interval=10,rdpct=0,openflags=o_direct,iorate=max,xfersize=256K,seekpct=0,maxdata=1,threads=1,pause=5m" >> /home/vdbench/$vdbench_sd_output

	echo "[INFO} vdbench config file was created: /home/vdbench/$vdbench_sd_output"
else
	echo "[INFO] Not running vdbench config creation"
fi

exit
