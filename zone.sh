#!/bin/bash
#
# Set the position of FC, from 0 to 3, make it a counter startig from 0.
# conuter=0
# then issue the following using the counter - xcli.py -z fc_port_list |awk '{print $4}'|grep "${counter}0$"
# for each listed FC added it an fc_array one by one
# repeat the above for next counter till 3 (including 3)
# the results will be fc_array of wwpn starting for the FC position at 0 till position 3.
# now we can zone single Initiator to first fc on each module, second fc on each module etc
#
hostlist=(rmhost1 rmhost2 rmhost3)
system_name="ba-55-nvme"
zone_mode="S"
function indexof {
i=0;
while [ "$i" -lt "${#array_fc[@]}" ] && [ "${array_fc[$i]}" != "$1" ]; do
	((i++));
done;
echo $i;
#return $i
}
#
### main ###
fccon_hosts=""
for host in "${hostlist[@]}";do 
	fccon_hosts="${fccon_hosts} -host ${host}"
done
echo $fccon_hosts
ssh stcon "/opt/FCCon/fcconnect.pl -op DisConnect -stor ${system_name} ${fccon_hosts}"
#total_fc=`xcli.py -z fc_port_list|wc -l`
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
for host in "${hostlist[@]}";do 
#    if [[ $? -ne 0 ]]; then
#        echo "[ERROR] No netwrok connectivity to host $host, ping failed. Existing"
#        exit 1
#    fi
    ssh $system_name xcli.py host_delete host=${host} -y 1>/dev/null
    host_fc_wwpn_list=`ssh $host cat /sys/class/fc_host/host*/port_name|cut -f2 -d "x"`
    zone=1
    for host_fc_wwpn in $host_fc_wwpn_list;do
#        echo $host_fc_wwpn
#        echo ${array_fc[$fc_counter]}
        ssh stcon /opt/FCCon/fcconnect.pl -op CreateZone -zone Z_${system_name}-${host}_${zone} -wwn $host_fc_wwpn -wwn ${array_fc[$fc_counter]}
        # The following code will define each host FC as a logical host on the storage
        ssh $system_name xcli.py host_define host=${host}-${zone} 1>/dev/null
        ssh $system_name xcli.py host_add_port host=${host}-${zone} fcaddress=$host_fc_wwpn 1>/dev/null
        ((zone++))
        ((fc_counter++))
        if [[ $fc_counter -gt $a9k_total_fc ]];then
            fc_counter=0
        fi
    done
done
