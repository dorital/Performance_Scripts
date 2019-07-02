#!/bin/bash
#
# This script gets as input: system_name, active dataset and volume number. 
# This script has internal definitions of host_list, protocol, system clean, system setup.
# Then it creates basic vdbench output
#
#
# General Script Setup
to_unmap_volumes="yes" 
to_map_volumes="no"
is_it_iSCSI="no"
is_it_vlan="no"
is_it_nvme="no"
system_name="ba-55-nvme"
pool_name="perf_pool1"
hostlist=(rmhost1 rmhost2 rmhost3)

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
	native_multipath=`ssh $host "cat /sys/module/nvme_core/parameters/multipath"`
	if [ $native_multipath == "N" ];then
		ssh $host multipath -F > /dev/null
		ssh $host service multipathd stop > /dev/null
		ssh $host rescan-scsi-bus.sh -f -r > /dev/null
		sleep 5
		ssh $host service multipathd start > /dev/null
	fi
done

}

function map_volumes {
if [ $is_it_nvme == "yes" ]; then
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
else
	echo "`date +%F_%H%M` [INFO] Requested FC configuration is SCSI"
	echo "`date +%F_%H%M` [INFO] Configuring all FC cards protocol on system $system_name to be SCSI"	
	for fc_port in `ssh $system_name xcli.py fc_port_list -z|awk '{print $1}'`;do 
		ssh $system_name xcli.py fc_port_config fc_port=$fc_port protocol=SCSI 1>/dev/null
	done
	sleep 20
	echo "[INFO] system $system_name FC SCSI ports:"
	ssh $system_name xcli.py fc_port_list -f component_id,protocol
fi
echo "`date +%F_%H%M` [INFO] Start vol mapping on system $system_name"
index=0
for a9k_host in `ssh $system_name xcli.py -z host_list |grep "default"|awk '{print $1}'`;do
    a9k_array_hosts[$index]=$a9k_host
    ((index++))
done
a9k_total_hosts=`echo ${#a9k_array_hosts[@]}`
a9k_total_volumes=`ssh $system_name xcli.py -z vol_list pool=${pool_name}|wc -l`
echo "total number of hosts: ${a9k_total_hosts}"
echo "total number of volumes: ${a9k_total_volumes}"
echo "defined host names: ${a9k_array_hosts[@]}"
host_mapping=`echo "$a9k_total_volumes/$a9k_total_hosts"|bc`
vol_map=1
#
for host in "${a9k_array_hosts[@]}";do
	echo "[INFO] Start - volume mapping host $host"
	for i in $(seq 1 $host_mapping);do
	   ssh $system_name xcli.py map_vol host=$host lun=${vol_map} vol=perf_${pool_name}_${vol_map} 1>/dev/null
	   ((vol_map++))
	done
	native_multipath=`ssh $host "cat /sys/module/nvme_core/parameters/multipath"`
	if [ $native_multipath == "N" ];then
		ssh $host multipath -F > /dev/null
		ssh $host service multipathd stop > /dev/null
		if [ $is_it_nvme == "no" ]; then
			ssh $host rescan-scsi-bus.sh > /dev/null
		fi
		ssh $host service multipathd start > /dev/null
	fi
	echo "[INFO] End - volume mapping host $host"
	#
done
echo "`date +%F_%H%M` [INFO] End vol mapping on system $system_name"

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

#@echo "Script input parms are: "$@
#@echo "Script internal parms are:"
echo -e "to_unmap_volumes:\t"$to_unmap_volumes
echo -e "to_map_volumes:\t\t"$to_map_volumes
echo -e "is_it_iSCSI:\t\t"$is_it_iSCSI
echo -e "is_it_nvme:\t\t"$is_it_nvme
echo -e "system name:\t\t"$system_name
echo -e "pool name is:\t\t"$pool_name
echo -e "press enter to continue"
read nu

#
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
if [ $to_map_volumes == "yes" ];then
	echo "[INFO] Running volumes mapping"
	map_volumes
else
	echo "[INFO] Not running volumes mapping"
fi

exit
#
#echo "nu2?"
#read nu
