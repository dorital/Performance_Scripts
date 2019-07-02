#!/bin/bash
#
# This script has internal definitions for: number of ESXi hosts, VVol size, number of VM per ESXi host, system name, test name
# This script does the following:
# 1. Builds an array (array_vm_ip) for all vm' IP addresses to be used as hosts in vdbench based on the overall number of VMs
# 2. Creates the vdbench config file using the VM's IPs as host and getting the block devices from each VM for SD. Then
#    It creates the vdbench config file with 6_common test cases
# 3. Then manaully you can run the craeted vdbecnh config file from perf-util
#
# This script should be run on perf-util
#
# NOTE: Do not use to large scale test.
#
# 
vol_size=25
number_of_esxi=1
vm_per_esxi=180
number_of_vm=`echo $(($number_of_esxi*$vm_per_esxi))`
to_create_vdbench="yes"
system_name="gen4d-pod-331"
test_name="perf_vvol"
#hostlist=(tile2 tile3 tile4 tile5 tile6 tile7 tile8 tile9)

function indexof {
i=0;
while [ "$i" -lt "${#array_vm_ip[@]}" ] && [ "${array_vm_ip[$i]}" != "$1" ]; do
	((i++));
done;
echo $i;
#return $i
}
#
### main ###
#@if [ $# != 3 ];then
#@	echo "sample: $0 system_name active_dataset_size_GB test_name"
#@	exit
#@fi
#@system_name=$1
#@active_dataset=$2
#@test_name=$3
#interface=`echo $4|awk '{print tolower($1)}'`
index=0
messages_vm_ip=`cat /var/log/messages|grep "DHCPOFFER.*00:50:56:b1"|wc -l`
if [[ $messages_vm_ip -ge $number_of_vm ]];then
	for vm_ip in `cat /var/log/messages|grep "DHCPOFFER.*00:50:56:b1"|tail -n $number_of_vm|awk '{print $8}'`;do
		echo $vm_ip
		array_vm_ip[$index]=$vm_ip
		if [[ `cat /root/.ssh/known_hosts|grep -w $vm_ip` ]];then
			:
		else
			echo "$vm_ip ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBP9is4DJkHL2FCQcYKw0MBQWetJIHM4bVj6DrmMv+mshtAdyEs2o1KpYFMyP95+1AGMp+/CmiG8swBUNqkAVUtY=" >> /root/.ssh/known_hosts
		fi
		((index++))
	done
else
	old_messages=`ls -l /var/log/messages*|tail -1|awk '{print $9}'`
	old_messages_vm_ip=`echo $(($number_of_vm-$messages_vm_ip))`
	for vm_ip in `cat /var/log/messages|grep "DHCPOFFER.*00:50:56:b1"|tail -n $messages_vm_ip|awk '{print $8}'`;do
		echo $vm_ip
		array_vm_ip[$index]=$vm_ip
		if [[ `cat /root/.ssh/known_hosts|grep -w $vm_ip` ]];then
			:
		else
			echo "$vm_ip ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBP9is4DJkHL2FCQcYKw0MBQWetJIHM4bVj6DrmMv+mshtAdyEs2o1KpYFMyP95+1AGMp+/CmiG8swBUNqkAVUtY=" >> /root/.ssh/known_hosts
		fi
		((index++))
	done
	for vm_ip in `cat $old_messages|grep "DHCPOFFER.*00:50:56:b1"|tail -n $old_messages_vm_ip|awk '{print $8}'`;do
		echo $vm_ip
		array_vm_ip[$index]=$vm_ip
		if [[ `cat /root/.ssh/known_hosts|grep -w $vm_ip` ]];then
			:
		else
			echo "$vm_ip ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBP9is4DJkHL2FCQcYKw0MBQWetJIHM4bVj6DrmMv+mshtAdyEs2o1KpYFMyP95+1AGMp+/CmiG8swBUNqkAVUtY=" >> /root/.ssh/known_hosts
		fi
		((index++))
	done
fi
#
echo "Script input parms are: "$@
echo "Script internal parms are:"
echo -e "to_create_vdbench:\t"$to_create_vdbench
echo -e "VM list:\t\t"${array_vm_ip[@]}
echo -e "system name:\t\t"$system_name
echo -e "test name:\t\t"$test_name
echo -e "vvol size:\t\t"$vol_size
echo -e "number of ESXi:\t\t"$number_of_esxi
echo -e "number of vm per ESXi:\t"$vm_per_esxi
echo -e "Total number of VMs:\t"$number_of_vm
echo -e "press enter to continue"
read nu
#
#exit
#
if [ $to_create_vdbench == "yes" ];then
	echo "[INFO] Running vdbench config creation"
	sd=0
	vdbench_vol_size=`echo "$vol_size/1.1"|bc`
	vdbench_sd_output="VVol_${system_name}_VM${number_of_vm}_vdbench_config"
	rm -f /root/vdbench/$vdbench_sd_output
	echo "compratio=2.86" > /root/vdbench/$vdbench_sd_output
	echo "#dedupratio=2,dedupunit=8k,dedupsets=5%" >> /root/vdbench/$vdbench_sd_output
	echo "debug=25" >> /root/vdbench/$vdbench_sd_output
	echo "hd=default,vdbench=/root/vdbench//bin,user=root,shell=ssh" >> /root/vdbench/$vdbench_sd_output
	for vm in "${array_vm_ip[@]}";do 
		hd=$( indexof $vm )
		echo "hd=hd$hd,system=$vm" >> /root/vdbench/$vdbench_sd_output
	done
	#
	for vm in "${array_vm_ip[@]}";do 
		hd=$( indexof $vm )
		for dm in `ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $vm "ls /dev/sd*|grep -v sda"`;do
			echo "sd=sd$sd,host=hd$hd,lun=$dm,openflags=(o_direct,o_sync,fsync),size=${vdbench_vol_size}g,threads=10,hitarea=170m" >> /root/vdbench/$vdbench_sd_output
			((sd++))
		done
	done
	echo "rd=default,xfersize=8k,iorate=max,elapsed=10m,interval=10,openflags=o_direct,hitarea=500m,pause=30m" >> /root/vdbench/$vdbench_sd_output
	echo "#rd=default,xfersize=8k,iorate=curve,curve=(10,25,50,65,70,80,90,100),elapsed=30m,interval=10,openflags=o_direct,hitarea=${hitarea}m,pause=30m" >> /root/vdbench/$vdbench_sd_output
	echo "rd=prealloc,sd=*,elapsed=100h,interval=10,rdpct=0,openflags=o_direct,iorate=max,xfersize=256K,seekpct=0,maxdata=1,threads=1,pause=5m" >> /root/vdbench/$vdbench_sd_output
	echo "rd=warmup,sd=*,elapsed=20m,interval=10,openflags=o_direct,iorate=max,xfersize=1m,rhpct=100,whpct=100,pause=1m" >> /root/vdbench/$vdbench_sd_output
	echo "rd=Read_Hit_8K,sd=*,rhpct=100,whpct=100,pause=1m" >> /root/vdbench/$vdbench_sd_output
	echo "rd=Read_Miss_8K,sd=*,rdpct=100,pause=1m" >> /root/vdbench/$vdbench_sd_output
	echo "rd=70_30_8K,sd=*,rdpct=70" >> /root/vdbench/$vdbench_sd_output
	echo "rd=70_30_80%_Hit_8K,sd=*,rdpct=70,rhpct=80,whpct=72" >> /root/vdbench/$vdbench_sd_output
	echo "rd=Write_Hit_8K,sd=*,rdpct=0,rhpct=100,whpct=100" >> /root/vdbench/$vdbench_sd_output
	echo "rd=Write_Miss_8K,sd=*,rdpct=0" >> /root/vdbench/$vdbench_sd_output
	echo "[INFO} vdbench config file was created: /root/vdbench/$vdbench_sd_output"
else
	echo "[INFO] Not running vdbench config creation"
fi

exit
