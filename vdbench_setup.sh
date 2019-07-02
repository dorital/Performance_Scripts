#!/bin/bash
#
# This script gets as input: system_name, active dataset and volume number. 
# This script has internal definitions of host_list, protocol, system clean, system setup.
# Then it creates basic vdbench output
#
#
# General Script Setup
to_clean_system="no"
to_unmap_volumes="no" 
to_do_fccon="no"
to_setup_system="no"
to_create_vdbench="yes"
is_it_iSCSI="no"
is_it_vlan="no"
is_it_nvme="yes"
system_name="ba-55-nvme"
active_dataset=32000
vol_number=120
total_threads=2400
pool_name="perf_pool1"
hostlist=(rmhost1 rmhost2 rmhost3)
zone_mode="F" #F-Full, H-Half, S-Single
#one-to-one="yes"  # only relevant for Sinle zone mode, defining each host FC and logical host on the storage
#hostlist=(mc015 mc017 mc018 wl21 wl23 wl24)
#hostlist=(rmhost2)
#host_list='mc028 mc029 mc031 mc032 mc034 mc035 mc036 mc051 mc052 mc069'

function unmap_volumes {
echo "`date +%F_%H%M` [INFO] Start - unmap volumes on system $system_name"
vol_unmap_list=`ssh $system_name xcli.py -z mapping_list|awk '{print $2}'`
for vol_unmap in $vol_unmap_list;do
	unmap_host=`ssh $system_name xcli.py vol_mapping_list vol=$vol_unmap -z | awk '{print $1}'`
	ssh $system_name xcli.py unmap_vol vol=$vol_unmap host=$unmap_host -y 1> /dev/null
done
echo "`date +%F_%H%M` [INFO] End - vol unmap, delete and pool deletion"
for host in "${hostlist[@]}";do
	echo $host
	if [ $is_it_nvme == "yes" ];then
		pass
	else
		ssh $host rescan-scsi-bus.sh -f -r > /dev/null
		ssh $host multipath -F > /dev/null
		ssh $host service multipathd restart > /dev/null
	fi
done

}

function system_clean {
echo "`date +%F_%H%M` [INFO] Start - system $system_name cleanup"
echo "`date +%F_%H%M` [INFO] Start - vol unmap, delete and pool deletion"
vol_clean_list=`ssh $system_name xcli.py vol_list pool=$pool_name -z|awk '{print$1}'`
#vol_clean_list=`ssh $system_name xcli.py -z mapping_list|awk -F " " '{print $2}'`
for vol_clean in $vol_clean_list;do
	unmap_host=`ssh $system_name xcli.py vol_mapping_list vol=$vol_clean -z | awk '{print $1}'`
	ssh $system_name xcli.py unmap_vol vol=$vol_clean host=$unmap_host -y 1> /dev/null
	ssh $system_name xcli.py cg_remove_vol -y vol=$vol_clean 1> /dev/null
	ssh $system_name xcli.py vol_delete -y vol=$vol_clean 1> /dev/null
done
echo "`date +%F_%H%M` [INFO] End - vol unmap, delete and pool deletion"
echo "`date +%F_%H%M` [INFO] Start - cg and pool deletion"
ssh $system_name xcli.py cg_delete cg=cg_$pool_name 1> /dev/null
ssh $system_name xcli.py pool_delete -y pool=$pool_name 1> /dev/null
echo "`date +%F_%H%M` [INFO] End - cg and pool deletion"
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
echo "`date +%F_%H%M` [INFO] Start - host cleaning"
for host in "${hostlist[@]}";do
	echo $host
    ssh $system_name xcli.py host_delete host=$host -y 1> /dev/null
	if [ $is_it_nvme == "yes" ];then
		pass
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
	fi
#	ssh $host rescan-scsi-bus.sh -f -r > /dev/null
#	ssh $host multipath -F > /dev/null
done
echo "`date +%F_%H%M` [INFO] End - host cleaning"
echo "`date +%F_%H%M` [INFO] End - system $system_name cleanup"
#
}

function fccon {
# creating host list for stcon
echo "`date +%F_%H%M` [INFO] Start - deleting existing zones for ${system_name}"
#ssh stcon "/opt/FCCon/fcconnect.pl -op DisConnect -stor ${system_name} ${fccon_hosts}"
ssh stcon "/opt/FCCon/fcconnect.pl -op DisConnectAll -stor ${system_name}"
echo "`date +%F_%H%M` [INFO] End - deleting existing zones for ${system_name}"
#
if [ $zone_mode == "F" ]; then
	fccon_hosts=""
	for host in "${hostlist[@]}";do 
		fccon_hosts="${fccon_hosts} -host ${host}"
		echo $fccon_hosts
		ssh $system_name xcli.py host_delete host=${host} -y 1>/dev/null
		ssh $system_name xcli.py host_define host=${host} 1>/dev/null
		host_fc_wwpn_list=`ssh $host cat /sys/class/fc_host/host*/port_name|cut -f2 -d "x"`
		for host_fc_wwpn in $host_fc_wwpn_list;do
			ssh $system_name xcli.py host_add_port host=${host} fcaddress=$host_fc_wwpn 1>/dev/null
		done
	done
	echo "`date +%F_%H%M` [INFO] Start - creating new zones for ${system_name}, zone mode: full"
	ssh stcon "/opt/FCCon/fcconnect.pl -op Connect -stor ${system_name} ${fccon_hosts}"
	echo "`date +%F_%H%M` [INFO] End - creating new zones for ${system_name}, zone mode: full"
else
	index=0
	for a9k_fc_port in $(seq 0 3);do
		for a9k_fc_wwpn in `ssh $system_name xcli.py -z fc_port_list|grep "Target\|Online"|awk '{print $4}'|grep "${a9k_fc_port}$"`;do
			echo $a9k_fc_wwpn
			array_fc[$index]=$a9k_fc_wwpn
			((index++))
		done
	done
	a9k_total_fc=`echo ${#array_fc[@]}`
	echo $a9k_total_fc
	echo ${array_fc[@]}
	fc_counter=0
	if [ $zone_mode == "S" ]; then
		echo "`date +%F_%H%M` [INFO] Start - creating new zones for ${system_name}, zone mode: single"
		for host in "${hostlist[@]}";do 
			zone=1
			ssh $system_name xcli.py host_delete host=${host} -y 1>/dev/null
			ssh $system_name xcli.py host_delete host=${host}-${zone} -y 1>/dev/null
			host_fc_wwpn_list=`ssh $host cat /sys/class/fc_host/host*/port_name|cut -f2 -d "x"`
			zone=1
			for host_fc_wwpn in $host_fc_wwpn_list;do
				ssh stcon /opt/FCCon/fcconnect.pl -op CreateZone -zone Z_${system_name}-${host}_${zone} -wwn $host_fc_wwpn -wwn ${array_fc[$fc_counter]}
				# The following code will define each host FC as a logical host on the storage
				ssh $system_name xcli.py host_define host=${host}-${zone} 1>/dev/null
				ssh $system_name xcli.py host_add_port host=${host}-${zone} fcaddress=$host_fc_wwpn 1>/dev/null
				((zone++))
				((fc_counter++))
				echo $fc_counter
				if [[ $fc_counter -gt $a9k_total_fc ]];then
					fc_counter=0
				fi
			done
		done
		echo "`date +%F_%H%M` [INFO] End - creating new zones for ${system_name}, zone mode: single"
	else
		host_fc_wwpn_list=`ssh $host cat /sys/class/fc_host/host*/port_name|cut -f2 -d "x"`
		zone=1
		add_to_zone="yes"
		ssh $system_name xcli.py host_delete host=${host} -y 1>/dev/null
		ssh $system_name xcli.py host_define host=${host} 1>/dev/null
		for host_fc_wwpn in $host_fc_wwpn_list;do
			echo "`date +%F_%H%M` [INFO] Start - creating new zones for ${system_name}, zone mode: half"
			fccon_a9k=""
			for a9k_fc_wwpn in "${array_fc[@]}";do 
				if [[ "$add_to_zone" == "yes" ]]; then
					fccon_a9k="${fccon_a9k} -wwn ${a9k_fc_wwpn}"
					echo $fccon_a9k
					add_to_zone="no"
				else
					add_to_zone="yes"
				fi
			done
			ssh stcon /opt/FCCon/fcconnect.pl -op CreateZone -zone Z_${system_name}-${host}_${zone} -wwn $host_fc_wwpn ${fccon_a9k}
			ssh $system_name xcli.py host_add_port host=${host} fcaddress=$host_fc_wwpn 1>/dev/null
			((zone++))
			if [[ "$add_to_zone" == "yes" ]]; then
				add_to_zone="no"
			else
				add_to_zone="yes"
			fi
		done
		echo "`date +%F_%H%M` [INFO] End - creating new zones for ${system_name}, zone mode: half"
	fi
fi

}

function system_setup {
echo "`date +%F_%H%M` [INFO] Start system $system_name $interface setup"
if [ "$interface" == "iscsi" ]; then
	if [ "$is_it_vlan" == "yes" ]; then
		echo "`date +%F_%H%M` [INFO] Requested iSCSI is VLAN Tagging"
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
	echo "`date +%F_%H%M` [INFO] Requested FC configuration is NVMe"
	echo "`date +%F_%H%M` [INFO] Verifying FC cards on all modules on system $system_name support NVMe"
	for module in `ssh $system_name xcli.py module_list -z|awk '{print $1}'|awk -F":" '{print $3}'`;do
		for fc in `ssh $system_name ssh module-$module lspci -n | grep 1077|awk '{print $3}'|awk -F':' '{print $2}'`;do
			if [ $fc != "2261" ]; then
				echo "[ERROR] FC on module $module on system $system_name is $fc. It does not support NVMe"
				exit 1
			fi
		done
	done
	echo "`date +%F_%H%M` [INFO] Verifying FC cards firmware on all modules on system $system_name support NVMe"
	for fc_fw in `ssh $system_name xcli.py fc_port_list -x |grep "active_firmware"|awk -F'"' '{print $2}'`;do
		if [ $fc_fw != "8:9:1" ]; then
				echo "[ERROR] FC firmware on system $system_name is $fc_fw. It does not support NVMe"
				exit 1
		fi
	done
	echo "`date +%F_%H%M` [INFO] FC on system $system_name supports NVMe"
	echo "`date +%F_%H%M` [INFO] Configuring all FC cards protocol on system $system_name to be NVMe"	
	for fc_port in `ssh $system_name xcli.py fc_port_list -z|awk '{print $1}'`;do 
		ssh $system_name xcli.py fc_port_config fc_port=$fc_port protocol=NVMe 1>/dev/null
	done
	sleep 20
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
	if [ $to_do_fccon == "no" ]; then
		ssh $system_name xcli.py host_define host=$host 1>/dev/null
	fi
	echo "[INFO] Start - host definition $host using $interface"
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
		if [ $to_do_fccon == "no" ]; then
			host_fc_wwpn=`ssh $host cat /sys/class/fc_host/host*/port_name|cut -f2 -d "x"`
			for fc_wwpn in $host_fc_wwpn;do
			# Adding hosts wwpn on A9K system
				echo $fc_wwpn
				ssh $system_name xcli.py host_add_port host=$host fcaddress=$fc_wwpn 1>/dev/null
			done
		fi
		if [ $is_it_nvme == "yes" ];then
			echo "[INFO] Requested FC protocol is NVMe, verifying and configuring host $host to support NVMe"
			if [[ `ssh $host lspci |grep -i fibre|grep -i emulex` ]];then 
				echo "[INFO] Host $host has Emulex FC HBAs"
#				echo "[INFO] Verifying host $host FC firmware to support NVMe"
#				for host_fc_fw in `ssh $host /usr/sbin/linlpcfg/elxflash /q|grep -i firmware|awk -F "," '{print $8}'|awk -F "=" '{print $2}'`;do
#					if [ $host_fc_fw != "12.0.261.15" ]; then
#						echo "[ERROR] FC firmware $host_fc_fw on host $host does not support NVMe"
#						exit 1
#					fi
#				done
#				echo "[INFO] Verifying host $host FC driver to support NVMe"
#				for host_fc_driver in `ssh $host cat /sys/class/scsi_host/host*/lpfc_drvr_version|awk '{print $7}'`;do
#					if [ $host_fc_driver != "12.0.261.26" ]; then
#						echo "[ERROR] FC driver $host_fc_driver on host $host does not support NVMe"
#						exit 1
#					fi
#				done
			else
				echo "[INFO] Host $host has Qlogic FC HBAs"
				echo "[INFO] Verifying host $host FC firmware to support NVMe"
				for host_fc_fw in `ssh $host qaucli -i |grep "Running Firmware Version"|awk '{print $5}'`;do
					if [ $host_fc_fw != "8.09.01" ]; then
						echo "[ERROR] FC firmware $host_fc_fw on host $host does not support NVMe"
						exit 1
					fi
				done
				echo "[INFO] Verifying host $host FC driver to support NVMe"
				for host_fc_driver in `ssh $host qaucli -i |grep "Driver"|awk '{print $4}'|awk '{print $1}'`;do
					if [ $host_fc_driver != "10.01.00.23.15.0-k1" ]; then
						echo "[ERROR] FC driver $host_fc_driver on host $host does not support NVMe"
						exit 1
					fi
				done
			echo "[INFO] stopping multipath on host $host"
			ssh $host service multipathd stop
			fi 
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
echo -e "to_unmap_volumes:\t"$to_unmap_volumes
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
echo -e "number of threads::\t"$total_threads
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
if [ $to_unmap_volumes == "yes" ];then
	echo "[INFO] Running volumes unmap"
	unmap_volumes
else
	echo "[INFO] Not running volumes unmap"
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
#echo "nu2?"
#read nu
if [ $to_create_vdbench == "yes" ];then
	echo "[INFO] Running vdbench config creation"
	sd=0
	vdbench_vol_size=`echo "$vol_size/1.1"|bc`
	threads=`echo $(($total_threads/$vol_number))`
	vdbench_sd_output="${system_name}_${interface}_${active_dataset}GB_vdbench_config"
	rm -f /home/vdbench/$vdbench_sd_output
#	echo "compratio=2.86" > /home/vdbench/$vdbench_sd_output
	echo "compratio=3" > /home/vdbench/$vdbench_sd_output
	echo "#dedupratio=2,dedupunit=8k,dedupsets=5%" >> /home/vdbench/$vdbench_sd_output
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
			#ssh $host modprobe -r qla2xxx
			#sleep 5
			#ssh $host modprobe qla2xxx
			#sleep 15
			hd=$( indexof $host )
			native_multipath=`ssh $host "cat /sys/module/nvme_core/parameters/multipath"`
			if [ $native_multipath == "N" ];then
				echo "[INFO] - Using NVMe DMMP multipath on host ${host}"
				ssh $host "service multipathd restart" > /dev/null
				sleep 5
#				ssh $host "multipath -F" > /dev/null
#				sleep 5
#				ssh $host "multipath" > /dev/null
				for dm in `ssh $host multipath -ll |grep -i $system_serial_hex |cut -f2 -d"-"|cut -f1 -d" "|sort -n`;do
					echo "sd=sd$sd,host=hd$hd,lun=/dev/dm-$dm,openflags=(o_direct,o_sync,fsync),size=${vdbench_vol_size}g,threads=${threads},hitarea=170m" >> /home/vdbench/$vdbench_sd_output
					((sd++))
				done
			else
				echo "[INFO] - Using NVMe Native multipath on host ${host}"
				for nvme_dev in `ssh $host nvme list |grep -i $system_serial | awk '{print $1}'`;do
					echo "sd=sd$sd,host=hd$hd,lun=$nvme_dev,openflags=(o_direct,o_sync,fsync),size=${vdbench_vol_size}g,threads=${threads},hitarea=170m" >> /home/vdbench/$vdbench_sd_output
					((sd++))
				done
			fi
		done
	else
		for host in "${hostlist[@]}";do 
			echo "$host"
			ssh $host "multipath -F" > /dev/null
			ssh $host "service multipathd stop" > /dev/null
			sleep 5
			ssh $host "rescan-scsi-bus.sh" > /dev/null
			ssh $host "service multipathd start" > /dev/null
			sleep 5
			ssh $host "multipath" > /dev/null
			hd=$( indexof $host )
		#	indexof "$host"
		#	echo $?
		#	hd=$?
		#	echo $hd
		# use list of mapping volumes based on name,pool_name and wwn - xcli.py vol_list -f name,pool_name,wwn
		# for each volume checkon the host the attached mpath using the wwn
			for dm in `ssh $host multipath -ll |grep -i $system_serial_hex |cut -f2 -d"-"|cut -f1 -d" "|sort -n`;do  
				echo "sd=sd$sd,host=hd$hd,lun=/dev/dm-$dm,openflags=(o_direct,o_sync,fsync),size=${vdbench_vol_size}g,threads=${threads},hitarea=170m" >> /home/vdbench/$vdbench_sd_output
				((sd++))
			done
		done
	fi
	echo "#rd=default,xfersize=8k,iorate=curve,curve=(10,25,50,65,70,80,90,100),elapsed=10m,interval=10,openflags=o_direct,hitarea=500m,pause=30m" >> /home/vdbench/$vdbench_sd_output
	echo "#rd=default,xfersize=8k,iorate=max,elapsed=10m,interval=10,openflags=o_direct,hitarea=500m,pause=30m" >> /home/vdbench/$vdbench_sd_output
	echo "#rd=prealloc,sd=*,elapsed=100h,interval=10,rdpct=0,openflags=o_direct,iorate=max,xfersize=256K,seekpct=0,maxdata=1,threads=1,pause=5m" >> /home/vdbench/$vdbench_sd_output
	echo "#rd=warmup,sd=*,elapsed=20m,interval=10,openflags=o_direct,iorate=max,xfersize=1m,rhpct=100,whpct=100,pause=1m" >> /home/vdbench/$vdbench_sd_output
	echo "#rd=Read_Hit_8K,sd=*,rhpct=100,whpct=100,curve=(10,25,50,65,70,80,83,86,90,92,94,96,98,100),pause=1m" >> /home/vdbench/$vdbench_sd_output
	echo "#rd=Read_Miss_8K,sd=*,rdpct=100,curve=(10,25,50,65,70,80,83,86,90,92,94,96,98,100),pause=1m" >> /home/vdbench/$vdbench_sd_output
	echo "#rd=70_30_8K,sd=*,rdpct=70" >> /home/vdbench/$vdbench_sd_output
	echo "#rd=70_30_80%_Hit_8K,sd=*,rdpct=70,rhpct=80,whpct=72" >> /home/vdbench/$vdbench_sd_output
	echo "#rd=Write_Hit_8K,sd=*,rdpct=0,rhpct=100,whpct=100,pause=5m" >> /home/vdbench/$vdbench_sd_output
	echo "#rd=30min_pause_4_8k,sd=*,rdpct=100,elapsed=1m,interval=30,iorate=1,pause=30m" >> /home/vdbench/$vdbench_sd_output
	echo "#rd=Write_Miss_8K,sd=*,rdpct=0" >> /home/vdbench/$vdbench_sd_output
	echo "[INFO} vdbench config file was created: /home/vdbench/$vdbench_sd_output"
else
	echo "[INFO] Not running vdbench config creation"
fi
if [[ $to_collect_total_results == "yes" ]];then
    echo "`date +%F_%H%M` [INFO] Start - collecting total results"
    results="/var/tmp/VVol_Results/results_${current_date}.csv"
    rm -f ${results}
    for orchestarte_vm in "${list_vdbench_orchestrate_vm_ip[@]}";do
        vdbench_orchestrate_index=$( index_vdbench_orchestrate_vm_ip $orchestarte_vm )
        total_results=`ssh $orchestarte_vm ls -lrt /var/tmp/ |tail -1|awk '{print $9}'`
        scp $orchestarte_vm:/var/tmp/${total_results}/totals.html /var/tmp/VVol_Results/${total_results}_totals.html
        filename="/var/tmp/VVol_Results/${total_results}_totals.html"
        echo ${hostlist[vdbench_orchestrate_index]} >> ${results}
        echo "`date +%F_%H%M` [INFO] collecting total results for ${hostlist[vdbench_orchestrate_index]}"
        #records=`cat ${results_dir}totals.html |grep "RD=\|avg"`
        while read -r line; do
            rec="$line"
        #for rec in `cat ${results_dir}totals.html |grep "RD=\|avg"`;do
        #    "Printing RD statement"
            if [[ `echo $rec|grep "RD="` ]];then
                test=`echo $rec |awk -F";" '{print $1}'|awk -F"RD=" '{print $2}'`
                echo -n $test" " >> ${results}
        #    "Printing test results"
            elif [[ `echo $rec|grep "avg"` ]];then
                echo $rec |awk '{printf $1" "; {for(i=3;i<=NF;i++) printf $i" "} print ""; }' >> ${results}
            fi
        #done
        done < "$filename"
    echo "`date +%F_%H%M` [INFO] End - collecting total results. Results file is: ${results}"
    done
else
	echo "`date +%F_%H%M` [INFO] Not collecting total results"
fi
exit
