#!/bin/bash
#
# This script has internal definitions for: number of ESXi hosts, VVol size, number of VM per ESXi host, system name, test name
# This script does the following:
# 1. It can builds an array (array_vm_ip) for all vm' IP addresses to be used as hosts in vdbench based on the overall number of VMs.
# 2. It can create a vdbench config file using the VM's IPs as host and getting the block devices from each VM for SD per each ESXi host.
#    Then it copies the vdbench config file to each VM. So each VM has its own vdbench config file.
# 3. It can run the vdbench config files on all VM.
# 5. It can collect the vdbench results from all orchetrators and create one results csv.
#
# This script should be run on perf-util.
# This script supports large scale tests
#
# 
vol_size=2.5
vm_per_esxi=180
system_name="gen4d-pod-331"
system_type="br"
system_model="pod"
test_name="perf_vvol"
to_get_vm_ip="yes" # <== access all VMs, get their IP and build array "array_vm_ip"
to_create_vdbench="no" # <== craete the vdbench config file for each tile host for its VMs
to_setup_ESXi_RR_QD="no"
to_run_vdbench="yes" # <== run the vdbench workload, all vdbench orchestrate VM will start vdbecnh on all tile VMs
to_collect_total_results="no" #<== collect the total.html results from all vdbench orchestrate VM
#hostlist=(tile2 tile3 tile4 tile5 tile6 tile7 tile8 tile9 tile10 tile11 tile12 tile13 tile14 tile15 tile16 tile17 tile18 tile19 tile20)
hostlist=(tile1 tile2 tile3 tile4 tile5 tile6 tile7 tile8 tile9 tile10)
number_of_esxi=${#hostlist[@]}
number_of_vm=`echo $(($number_of_esxi*$vm_per_esxi))`
ip_duplication=2
number_of_ip=`echo $(($number_of_vm+$ip_duplication))`
# BR pod hitarea for per module is 15GB
# BR rack hitarea for per module is 39GB
# BA hitarea for per module is 28GB
# hitarea = hit_area_per_module * #_of_modules / #_of_vvols, for example BR-POD 15GB*3/3540 = 13MB
hitarea=12
#hitarea=echo "vault_limit_num_schedules*num_schedules*num_modules*0.9/num_vvols"|bc

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
if [ $to_get_vm_ip == "yes" ];then
    index=0
    vm_ip_file="/root/vdbench/vm_ip_file.txt"
    rm -f $vm_ip_file
    touch $vm_ip_file
    messages_vm_ip=`cat /var/log/messages|grep "DHCPOFFER.*00:50:56:b1"|wc -l`
    if [[ $messages_vm_ip -ge $number_of_ip ]];then
        for vm_ip in `cat /var/log/messages|grep "DHCPOFFER.*00:50:56:b1"|tail -n $number_of_ip|awk '{print $8}'`;do
            fgrep -w $vm_ip $vm_ip_file
            if [[ $? -ne 0 ]];then
                array_vm_ip[$index]=$vm_ip
                echo $vm_ip >> $vm_ip_file
                ((index++))
            else
                echo "[WARNNING] - IP ${vm_ip} alraedy exists"
                ((number_of_vm++))
            fi                
            if [[ `cat /root/.ssh/known_hosts|grep -w $vm_ip` ]];then
                :
            else
                echo "$vm_ip ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBP9is4DJkHL2FCQcYKw0MBQWetJIHM4bVj6DrmMv+mshtAdyEs2o1KpYFMyP95+1AGMp+/CmiG8swBUNqkAVUtY=" >> /root/.ssh/known_hosts
            fi
        done
    else
        old_messages=`ls -l /var/log/messages*|tail -1|awk '{print $9}'`
        old_messages_vm_ip=`echo $(($number_of_ip-$messages_vm_ip))`
        for vm_ip in `cat /var/log/messages|grep "DHCPOFFER.*00:50:56:b1"|tail -n $messages_vm_ip|awk '{print $8}'`;do
            fgrep -w $vm_ip $vm_ip_file
            if [[ $? -ne 0 ]];then
                array_vm_ip[$index]=$vm_ip
                echo $vm_ip >> $vm_ip_file
                ((index++))
            else
                echo "[WARNNING] - IP ${vm_ip} alraedy exists"
                ((number_of_vm++))
            fi                
            if [[ `cat /root/.ssh/known_hosts|grep -w $vm_ip` ]];then
                :
            else
                echo "$vm_ip ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBP9is4DJkHL2FCQcYKw0MBQWetJIHM4bVj6DrmMv+mshtAdyEs2o1KpYFMyP95+1AGMp+/CmiG8swBUNqkAVUtY=" >> /root/.ssh/known_hosts
            fi
        done
        for vm_ip in `cat $old_messages|grep "DHCPOFFER.*00:50:56:b1"|tail -n $old_messages_vm_ip|awk '{print $8}'`;do
            fgrep -w $vm_ip $vm_ip_file
            if [[ $? -ne 0 ]];then
                array_vm_ip[$index]=$vm_ip
                echo $vm_ip >> $vm_ip_file
                ((index++))
            else
                echo "[WARNNING] - IP ${vm_ip} alraedy exists"
                ((number_of_vm++))
            fi                
            if [[ `cat /root/.ssh/known_hosts|grep -w $vm_ip` ]];then
                :
            else
                echo "$vm_ip ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBP9is4DJkHL2FCQcYKw0MBQWetJIHM4bVj6DrmMv+mshtAdyEs2o1KpYFMyP95+1AGMp+/CmiG8swBUNqkAVUtY=" >> /root/.ssh/known_hosts
            fi
        done
    fi
    echo $number_of_ip $number_of_vm
    if [[  $number_of_ip -ne $number_of_vm ]]; then
        echo "[ERROR] - IP duplication, less IP than required. Please set ip_duplication to `echo $(($number_of_vm-$number_of_ip))`"
        exit 1
    fi
fi
#
echo "Script input parms are: "$@
echo "Script internal parms are:"
#echo -e "VM list:\t\t"${array_vm_ip[@]}
echo -e "to get vm ip:\t\t"$to_get_vm_ip
echo -e "VM list file:\t\t"$vm_ip_file
echo -e "to create vdbench:\t"$to_create_vdbench
echo -e "to setup ESXi RR & QD:\t"$to_setup_ESXi_RR_QD
echo -e "to run vdbench:\t\t"$to_run_vdbench
echo -e "to collect results:\t"$to_collect_total_results
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
vdbench_sd_output="VVol_${system_name}_ESXi${number_of_esxi}_VM${number_of_vm}_vdbench_config"
if [ $to_create_vdbench == "yes" ];then
	echo "`date +%F_%H%M` [INFO] Running vdbench config creation"
	vdbench_vol_size=`echo "$vol_size/1.1"|bc`
#    rm -f /root/vdbench/${vdbench_sd_output}*
    for vm in "${array_vm_ip[@]}";do
        echo "compratio=2.86" > /root/vdbench/$vdbench_sd_output
        echo "#dedupratio=2,dedupunit=8k,dedupsets=5%" >> /root/vdbench/$vdbench_sd_output
        echo "debug=25" >> /root/vdbench/$vdbench_sd_output
        sd=0 
        for dm in `ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $vm "ls /dev/sd*|grep -v sda"`;do
            echo "sd=sd$sd,lun=$dm,openflags=(o_direct,o_sync,fsync),size=${vdbench_vol_size}g,threads=10,hitarea=${hitarea}m" >> /root/vdbench/${vdbench_sd_output}
            ((sd++))
        done
        echo "#rd=default,xfersize=8k,iorate=max,elapsed=30m,interval=10,openflags=o_direct,hitarea=${hitarea}m,pause=30m" >> /root/vdbench/${vdbench_sd_output}
        echo "rd=default,xfersize=8k,iorate=curve,curve=(10,25,50,65,70,80,90,100),elapsed=30m,interval=10,openflags=o_direct,hitarea=${hitarea}m,pause=30m" >> /root/vdbench/${vdbench_sd_output}
        echo "rd=prealloc,sd=*,elapsed=100h,interval=10,rdpct=0,openflags=o_direct,iorate=max,xfersize=256K,seekpct=0,maxdata=1,threads=1,pause=5m" >> /root/vdbench/${vdbench_sd_output}
        echo "rd=warmup,sd=*,elapsed=20m,interval=10,openflags=o_direct,iorate=max,xfersize=1m,rhpct=100,whpct=100" >> /root/vdbench/${vdbench_sd_output}
        echo "rd=Read_Hit_8K,sd=*,rhpct=100,whpct=100" >> /root/vdbench/${vdbench_sd_output}
        echo "rd=Read_Miss_8K,sd=*,rdpct=100" >> /root/vdbench/${vdbench_sd_output}
        echo "rd=70_30_8K,sd=*,rdpct=70" >> /root/vdbench/${vdbench_sd_output}
        echo "rd=70_30_80%_Hit_8K,sd=*,rdpct=70,rhpct=80,whpct=72" >> /root/vdbench/${vdbench_sd_output}
        echo "rd=Write_Hit_8K,sd=*,rdpct=0,rhpct=100,whpct=100" >> /root/vdbench/${vdbench_sd_output}
        echo "rd=Write_Miss_8K,sd=*,rdpct=0" >> /root/vdbench/${vdbench_sd_output}
#        echo "`date +%F_%H%M` [INFO} Start - Copy vdbench config file /root/vdbench/${vdbench_sd_output} $vm under ~/vdbench"
        scp /root/vdbench/${vdbench_sd_output} $vm:/root/vdbench/
#        echo "`date +%F_%H%M` [INFO} End - Copy vdbench config file /root/vdbench/${vdbench_sd_output} $vm under ~/vdbench"
    done
else
	echo "`date +%F_%H%M` [INFO] Not creating vdbench config"
fi
if [ $to_setup_ESXi_RR_QD == "yes" ];then
    for host in "${hostlist[@]}";do
        host_ip=`cat /etc/dhcp/dhcpd.conf |grep -w $host|awk -F " |;" '{print $9}'`
        ping -c1 $host_ip > /dev/null
        if [[ $? -ne 0 ]];then
            echo "`date +%F_%H%M` [ERROR] No netwrok connectivity to host $host, ping failed. Existing"
            exit 1
        fi
        echo "`date +%F_%H%M` [INFO] Start - Setting host $host multipath and queue depth"
        for dev in `ssh $host_ip esxcli storage core device list |grep ^"naa."`;do
            dev_pe=`ssh $host_ip esxcli storage core device list -d $dev|grep "PE"|awk '{print $4}'`
            dev_model=`ssh $host_ip esxcli storage core device list -d $dev|grep "2810"|awk '{print $2}'`
            if [[ "$dev_pe" = "true" ]] || [[ "$dev_model" = "2810XIV" ]];then
                echo $dev
            #if ( `ssh perf-proxy ssh $host_ip esxcli storage core device list -d $dev|grep "PE"|awk '{print $4}'` -eq "true" );then
                #echo $dev_pe $dev_model
                #ssh perf-proxy ssh $host_ip "esxcli storage nmp device set -d $dev -P VMW_PSP_RR"
                # setting the round robin policy to switch path after every IO, increases performance 
                ssh $host_ip "esxcli storage nmp psp roundrobin deviceconfig set -d $dev --type=iops --iops=1"
                # increasing the PE max queue depth to 64 which is equal to the HBA setting
                hba_max_qd=`ssh $host_ip esxcli storage core device list -d $dev|grep Max|awk -F":" '{print $2}'|sed 's/ //g'`
                pe_max_qd=`ssh $host_ip esxcli storage core device list -d $dev|grep IOs|awk -F":" '{print $2}'|sed 's/ //g'`
                if [[ $hba_max_qd -gt $pe_max_qd ]]; then
                    ssh $host_ip "esxcli storage core device set -O $hba_max_qd -d $dev"
                fi
                ssh $host_ip esxcli storage nmp device list -d $dev|grep "policy"
                ssh $host_ip esxcli storage core device list -d $dev|grep "Max\|IOs"
            fi	
        done
        echo "`date +%F_%H%M` [INFO] End - Setting host $host multipath and queue depth"
    done
fi
#
echo "nu1?"
read nu
run=0
vm_num=0
#rm -f run_$run
rm -f run_${hostlist[$run]}
if [[ $to_run_vdbench == "yes" ]];then
    for vm in "${array_vm_ip[@]}";do
        echo "${vm}"
 #       echo 'ssh $vm "sh -c \"(nohup date) > dori.date &\""' >> run_$run
        echo "ssh ${vm} 'sh -c \"(nohup date) > dori.date &\"'" >> run_${hostlist[$run]}
        ((vm_num++))
        if [[ $vm_num -eq $vm_per_esxi ]]; then
            echo "file run_${hostlist[$run]} is ready"
            vm_num=0
            chmod +x run_${hostlist[$run]}
            ((run++))
            rm -f run_${hostlist[$run]}
        fi
    done
    echo "nu2?"
    read nu
    for file in "${hostlist[@]}";do
#        chmod +x run_$file
        ./run_${file} &
    done
    echo "nu3?"
    read nu
    rm -f VM_dates
    for vm in "${array_vm_ip[@]}";do
        ssh $vm "sh -c \"(nohup cat dori.date) &\"" >> VM_dates
    done
else
	echo "`date +%F_%H%M` [INFO] Not running vdbench config"
fi
exit

filename="/root/vdbench/vm_ip_file.txt"
while read -r line; do
    ssh $line "sh -c \"(nohup date) > dori.date &\""
done < "$filename"
while read -r line; do
    ssh $line "sh -c \"(nohup date) > dori.date &\""
done < "$filename"

exit


