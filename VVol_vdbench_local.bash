#!/bin/bash
#
# This script has internal definitions for: number of ESXi hosts, VVol size, number of VM per ESXi host, system name, test name
# This script does the following:
# 1. It builds an array (array_vm_ip) for all vm' IP addresses to be used as hosts in vdbench based on the overall number of VMs.
# 2. It creates a vdbench config file using the VM's IPs as host and getting the block devices from each VM for SD per each ESXi host.
# 3. It runs the vdbench config files each on a different screen having a screen session for each ESXi. 
#
#  This script should be run on perf-util
#
# NOTE: Do not use to large scale test.
# 
vol_size=2.5
number_of_esxi=9
vm_per_esxi=180
number_of_vm=`echo $(($number_of_esxi*$vm_per_esxi))`
to_create_vdbench="yes"
system_name="gen4d-pod-331"
test_name="perf_vvol"
#hostlist=(tile2 tile3 tile4 tile5 tile6 tile7 tile8 tile9 tile10 tile11 tile12 tile13 tile14 tile15 tile16 tile17 tile18 tile19 tile20)
hostlist=(tile1 tile2 tile3 tile4 tile5 tile6 tile7 tile8 tile9)

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
		array_vm_ip[$index]=$vm_ip
		if [[ `cat /root/.ssh/known_hosts|grep -w $vm_ip` ]];then
			:
		else
			echo "$vm_ip ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBP9is4DJkHL2FCQcYKw0MBQWetJIHM4bVj6DrmMv+mshtAdyEs2o1KpYFMyP95+1AGMp+/CmiG8swBUNqkAVUtY=" >> /root/.ssh/known_hosts
		fi
		((index++))
	done
	for vm_ip in `cat $old_messages|grep "DHCPOFFER.*00:50:56:b1"|tail -n $old_messages_vm_ip|awk '{print $8}'`;do
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
	esxi_vm_count=1
    vdbench_orchestrate_index=0
    host_index=0
	vdbench_vol_size=`echo "$vol_size/1.1"|bc`
	vdbench_sd_output="VVol_${system_name}_VM${number_of_vm}_vdbench_config"
    rm -f /root/vdbench/${vdbench_sd_output}*
    #rm -f /root/vdbench/${vdbench_sd_output}_hd
    #rm -f /root/vdbench/${vdbench_sd_output}_sd
    #rm -f /root/vdbench/${vdbench_sd_output}_hd_all
    #rm -f /root/vdbench/${vdbench_sd_output}_sd_all
    #rm -f /root/vdbench/$vdbench_sd_output_${host}
    #rm -f /root/vdbench/${vdbench_sd_output}_${host}_hd
    #rm -f /root/vdbench/${vdbench_sd_output}_${host}_sd

    echo "compratio=2.86" > /root/vdbench/$vdbench_sd_output
    echo "#dedupratio=2,dedupunit=8k,dedupsets=5%" >> /root/vdbench/$vdbench_sd_output
    echo "debug=25" >> /root/vdbench/$vdbench_sd_output
    echo "hd=default,vdbench=/root/vdbench//bin,user=root,shell=ssh" >> /root/vdbench/$vdbench_sd_output
    echo "nu1?"
    read nu
#
    for vm in "${array_vm_ip[@]}";do 
        host=${hostlist[$host_index]}
        if [ $esxi_vm_count -lt $vm_per_esxi ]; then
            echo $esxi_vm_count
            ((esxi_vm_count++))
#            host={hostlist[$host_index]}
            hd=$( indexof $vm )
            echo "hd=hd$hd,system=$vm" >> /root/vdbench/${vdbench_sd_output}_${host}_hd
            for dm in `ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $vm "ls /dev/sd*|grep -v sda"`;do
                echo "sd=sd$sd,host=hd$hd,lun=$dm,openflags=(o_direct,o_sync,fsync),size=${vdbench_vol_size}g,threads=10,hitarea=170m" >> /root/vdbench/${vdbench_sd_output}_${host}_sd
                ((sd++))
            done
        else
            echo $host
#            host={hostlist[$host_index]}
#            list_vdbench_orchestrate_vm_ip[$vdbench_orchestrate_index]=$vm
#            (($vdbench_orchestrate_index++))
            hd=$( indexof $vm )
            echo "hd=hd$hd,system=$vm" >> /root/vdbench/${vdbench_sd_output}_${host}_hd
            for dm in `ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $vm "ls /dev/sd*|grep -v sda"`;do
                echo "sd=sd$sd,host=hd$hd,lun=$dm,openflags=(o_direct,o_sync,fsync),size=${vdbench_vol_size}g,threads=10,hitarea=170m" >> /root/vdbench/${vdbench_sd_output}_${host}_sd
                ((sd++))
            done
            echo "compratio=2.86" > /root/vdbench/${vdbench_sd_output}_${host}
            echo "#dedupratio=2,dedupunit=8k,dedupsets=5%" >> /root/vdbench/${vdbench_sd_output}_${host}
            echo "debug=25" >> /root/vdbench/${vdbench_sd_output}_${host}
            echo "hd=default,vdbench=/root/vdbench//bin,user=root,shell=ssh" >> /root/vdbench/${vdbench_sd_output}_${host}
            cat /root/vdbench/${vdbench_sd_output}_${host}_hd >> /root/vdbench/${vdbench_sd_output}_${host}
            cat /root/vdbench/${vdbench_sd_output}_${host}_sd >> /root/vdbench/${vdbench_sd_output}_${host}
            cat /root/vdbench/${vdbench_sd_output}_${host}_hd >> /root/vdbench/${vdbench_sd_output}_hd_all
            cat /root/vdbench/${vdbench_sd_output}_${host}_sd >> /root/vdbench/${vdbench_sd_output}_sd_all
            echo "rd=default,xfersize=8k,iorate=max,elapsed=10m,interval=10,openflags=o_direct,hitarea=500m,pause=30m" >> /root/vdbench/${vdbench_sd_output}_${host}
            echo "#rd=default,xfersize=8k,iorate=curve,curve=(10,25,50,65,70,80,90,100),elapsed=30m,interval=10,openflags=o_direct,hitarea=${hitarea}m,pause=30m" >> /root/vdbench/${vdbench_sd_output}_${host}
            echo "rd=prealloc,sd=*,elapsed=100h,interval=10,rdpct=0,openflags=o_direct,iorate=max,xfersize=256K,seekpct=0,maxdata=1,threads=1,pause=5m" >> /root/vdbench/${vdbench_sd_output}_${host}
            echo "#rd=warmup,sd=*,elapsed=20m,interval=10,openflags=o_direct,iorate=max,xfersize=1m,rhpct=100,whpct=100,pause=1m" >> /root/vdbench/${vdbench_sd_output}_${host}
            echo "#rd=Read_Hit_8K,sd=*,rhpct=100,whpct=100,pause=1m" >> /root/vdbench/${vdbench_sd_output}_${host}
            echo "#rd=Read_Miss_8K,sd=*,rdpct=100,pause=1m" >> /root/vdbench/${vdbench_sd_output}_${host}
            echo "#rd=70_30_8K,sd=*,rdpct=70,pause=30m" >> /root/vdbench/${vdbench_sd_output}_${host}
            echo "#rd=70_30_80%_Hit_8K,sd=*,rdpct=70,rhpct=80,whpct=72,pause=30m" >> /root/vdbench/${vdbench_sd_output}_${host}
            echo "#rd=Write_Hit_8K,sd=*,rdpct=0,rhpct=100,whpct=100,pause=30m" >> /root/vdbench/${vdbench_sd_output}_${host}
            echo "#rd=Write_Miss_8K,sd=*,rdpct=0" >> /root/vdbench/${vdbench_sd_output}_${host}
#            echo "[INFO} Coping ssh files /root/.ssh to $vm"
#            scp /root/.ssh/id_rsa* $vm:~/.ssh
#            scp /root/.ssh/known_hosts $vm:~/.ssh
#            echo "[INFO} Coping vdbench config file /root/vdbench/$vdbench_sd_output to $vm under ~/vdbench"
#            scp /root/vdbench/$vdbench_sd_output $vm:~/vdbench/
#            echo "[INFO} Setting up $vm for vdbench"
#            ssh $vm service firewalld stop
#            sleep 5
#            ssh $vm service firewalld status
#            ssh $vm hostnamectl set-hostname perf-vdbench
#            sleep 5
#            ssh $vm hostnamectl status
#            echo "[INFO} Copy of vdbench config file /root/vdbench/$vdbench_sd_output to $vm under ~/vdbench completed"
            echo "nu2?"
            read nu
            ((host_index++))      
            esxi_vm_count=1
#            rm -f /root/vdbench/$vdbench_sd_output
            rm -f /root/vdbench/${vdbench_sd_output}_${host}_hd
            rm -f /root/vdbench/${vdbench_sd_output}_${host}_sd
        fi
    done
    cat /root/vdbench/${vdbench_sd_output}_hd_all >> /root/vdbench/$vdbench_sd_output
    cat /root/vdbench/${vdbench_sd_output}_sd_all >> /root/vdbench/$vdbench_sd_output
    echo "rd=default,xfersize=8k,iorate=max,elapsed=10m,interval=10,openflags=o_direct,hitarea=500m,pause=30m" >> /root/vdbench/$vdbench_sd_output
    echo "#rd=default,xfersize=8k,iorate=curve,curve=(10,25,50,65,70,80,90,100),elapsed=30m,interval=10,openflags=o_direct,hitarea=${hitarea}m,pause=30m" >> /root/vdbench/$vdbench_sd_output
    echo "rd=prealloc,sd=*,elapsed=100h,interval=10,rdpct=0,openflags=o_direct,iorate=max,xfersize=256K,seekpct=0,maxdata=1,threads=1,pause=5m" >> /root/vdbench/$vdbench_sd_output
    echo "#rd=warmup,sd=*,elapsed=20m,interval=10,openflags=o_direct,iorate=max,xfersize=1m,rhpct=100,whpct=100,pause=1m" >> /root/vdbench/$vdbench_sd_output
    echo "#rd=Read_Hit_8K,sd=*,rhpct=100,whpct=100,pause=1m" >> /root/vdbench/$vdbench_sd_output
    echo "#rd=Read_Miss_8K,sd=*,rdpct=100,pause=1m" >> /root/vdbench/$vdbench_sd_output
    echo "#rd=70_30_8K,sd=*,rdpct=70,pause=30m" >> /root/vdbench/$vdbench_sd_output
    echo "#rd=70_30_80%_Hit_8K,sd=*,rdpct=70,rhpct=80,whpct=72,pause=30m" >> /root/vdbench/$vdbench_sd_output
    echo "#rd=Write_Hit_8K,sd=*,rdpct=0,rhpct=100,whpct=100,pause=30m" >> /root/vdbench/$vdbench_sd_output
    echo "#rd=Write_Miss_8K,sd=*,rdpct=0" >> /root/vdbench/$vdbench_sd_output
    echo "nu3?"
    read nu
    for host in "${hostlist[@]}";do
#    for orchestarte_vm in "${list_vdbench_orchestrate_vm_ip[@]}";do
        echo $host
        screen -dmS $host bash -c "/root/vdbench/bin/vdbench -f /root/vdbench/${vdbench_sd_output}_${host} -o /var/tmp/${vdbench_sd_output}_${host}/"
    done
#
#    for orchestarte_vm in "${list_vdbench_orchestrate_vm_ip[@]}";do
#        echo $orchestarte_vm
#        ssh $orchestarte_vm '"nohup /root/vdbench/bin/vdbench -f /root/vdbench/VVol_gen4d-pod-331_VM1620_vdbench_config -o /var/tmp/VVol_gen4d-pod-331_VM1620_vdbench_config" &'
#        ssh $orchestarte_vm "/root/vdbench/bin/vdbench -f /root/vdbench/$vdbench_sd_output -o /var/tmp/$vdbench_sd_output"
#    done

    #
else
	echo "[INFO] Not running vdbench config creation"
fi

exit
