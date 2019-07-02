#!/bin/sh
#
# This script gets as input: system_name, active dataset and volume number. 
# This script has internal definitions of host_list, protocol, system clean, system setup.
# Then it creates basic vdbench output
#
#
# General Script Setup
to_clean_system="no"
to_do_fccon="no"
to_setup_system="no"
to_create_vdbench="no"
is_it_iSCSI="no"
#hostlist=(rmhost7 rmhost8)
hostlist=(9.151.168.181)
#host_list='mc028 mc029 mc031 mc032 mc034 mc035 mc036 mc051 mc052 mc069'

function system_clean {
echo "[INFO] Start - system $system_name cleanup"
echo "[INFO] Start - vol unmap"
unmap_list=`ssh $system_name xcli.py -z mapping_list|awk -F " " '{print $2}'`
for unmap_vol in $unmap_list;do
   unmap_host=`ssh $system_name xcli.py vol_mapping_list vol=$unmap_vol -z | awk '{print $1}'`
   ssh $system_name xcli.py unmap_vol vol=$unmap_vol host=$unmap_host -y 1> /dev/null
done
echo "[INFO] End - vol unmap"
#
echo "[INFO] Start - pool cleaning"
pool_list=`ssh $system_name xcli.py -z pool_list|cut -f1 -d" "`
for pool in $pool_list;do
   vol_list=`ssh $system_name xcli.py -z vol_list pool=$pool |cut -f1 -d" "`
   for vol in $vol_list;do
#      ssh $system_name xcli.py unmap_vol -y vol=$vol
      ssh $system_name xcli.py cg_remove_vol -y vol=$vol 1> /dev/null
      ssh $system_name xcli.py vol_delete -y vol=$vol 1> /dev/null
   done
   ssh $system_name xcli.py pool_delete -y pool=$pool 1> /dev/null
done
echo "[INFO] End - pool cleaning"
#
echo "[INFO] Start - host cleaning"
host_clean=`ssh $system_name xcli.py -z host_list|cut -f1 -d" "`
for delete_host in $host_clean;do
    ssh $system_name xcli.py host_delete host=$delete_host -y 1> /dev/null
done
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
ssh stcon "/opt/FCCon/fcconnect.pl -op DisConnectAll -stor ${system_name}"
echo "[INFO] End - deleting all exiting zones for ${system_name}"
echo "[INFO] Start - creating new zones for ${system_name}"
# creating host list for stcon
fccon_hosts=""
for host in "${hostlist[@]}";do 
	fccon_hosts="${fccon_hosts} -host ${host}"
	echo $fccon_hosts
done
ssh stcon "/opt/FCCon/fcconnect.pl -op Connect -stor ${system_name} ${fccon_hosts}"
echo "[INFO] End - creating new zones for ${system_name}"
}

function system_setup {
echo "[INFO] Start system $system_name $interface setup"
if [ "$interface" == "iscsi" ]; then
	ssh $system_name /local/scratch/$system_name"_iscsi.sh"
	echo "$system_name iSCSI interfaces:"
	ssh $system_name xcli.py ipinterface_list | grep -i iscsi
fi
echo "[INFO] Start - pool creation"
pool_size=`echo "$active_dataset/0.9"|bc`
ssh $system_name xcli.py pool_create pool=$pool_name size=$pool_size snapshot_size=0 -y 1>/dev/null
echo "[INFO] End - pool creation"
#
echo "[INFO] Start - volume creation"
for vol in $(seq 1 $vol_number);do
   ssh $system_name   xcli.py vol_create pool=$pool_name size=$vol_size vol=perf_${pool_name}_${vol} 1>/dev/null
done
echo "[INFO] End - volume creation"
#
for host in "${hostlist[@]}";do
	echo "[INFO] Start - host definition $host using $interface"
	ssh $system_name xcli.py host_define host=$host 1>/dev/null
	if [ "$interface" == "iscsi" ]; then
		esxi_iscsi_adapter=`ssh $host esxcli iscsi adapter list | grep -i iscsi| awk '{print $1}'`
		host_iqn=`ssh 9.151.168.181 esxcli iscsi adapter get -A ${esxi_iscsi_adapter}|grep iqn|awk '{print $2}'`
		# Adding hosts iqn on A9K system
		ssh $system_name xcli.py host_add_port host=$host iscsi_name=$host_iqn > /dev/null
	else
		host_fc_wwpn=`ssh $host esxcli storage core adapter list |grep -i fibre|awk '{print $4}'|cut -f2 -d":"`
		for fc_wwpn in $host_fc_wwpn;do
		# Adding hosts wwpn on A9K system
			echo $fc_wwpn
			ssh $system_name xcli.py host_add_port host=$host fcaddress=$fc_wwpn 1>/dev/null
		done
	fi
	echo "[INFO] End - host definition $host"
#    for vol in $(seq $start_count $end_count);do
	echo "[INFO] Start - rescan on $host"
	ssh $host esxcli storage core adapter rescan --all
	echo "[INFO] End - rescan on $host"
	echo "[INFO] Start - volume mapping host $host"
    for lunid in $(seq 1 $host_mapping);do
   	   ssh $system_name xcli.py map_vol host=$host lun=$lunid vol=perf_${pool_name}_${vol_map} 1>/dev/null
	   ((vol_map++))
	done   
	echo "[INFO] End - volume mapping host $host"
	#
	ssh $host esxcli storage core adapter rescan --all
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
if [ $# != 3 ];then
	echo "sample: $0 system_name active_dataset_size_GB vol_number pool_name"
	exit
fi
system_name=$1
active_dataset=$2
vol_number=$3
pool_name=$4
#interface=`echo $4|awk '{print tolower($1)}'`

echo "Script input parms are: "$@
echo "Script internal parms are:"
echo -e "to_clean_system:\t"$to_clean_system
echo -e "to_do_fccon:\t\t"$to_do_fccon
echo -e "to_setup_system:\t"$to_setup_system
echo -e "to_create_vdbecnh:\t"$to_create_vdbecnh
echo -e "is_it_iSCSI:\t\t"$is_it_iSCSI
echo -e "host list:\t\t"${hostlist[@]}
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
if [ $to_create_vdbecnh == "yes" ];then
	echo "[INFO] Running vdbench config creation"
	sd=0
	vdbench_vol_size=`echo "$vol_size/1.1"|bc`
	vdbench_sd_output="${system_name}_${interface}_${active_dataset}GB_vdbench_config"
	rm -f /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
	echo "compratio=2.86" > /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
	echo "#dedupratio=2,dedupunit=8k,dedupsets=5%" >> /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
	echo "debug=25" >> /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
	echo "hd=default,vdbench=/root/vdbench/bin,user=root,shell=ssh" >> /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
	for host in "${hostlist[@]}";do 
		hd=$( indexof $host )
		echo "hd=hd$hd,system=$host" >> /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
	done
	#
	system_serial=`ssh $system_name xcli.py config_get |grep system_id |awk '{print $2}'`
	system_serial_hex=`echo "obase=16; $system_serial"|bc`
	for host in "${hostlist[@]}";do 
		echo "$host"
		ssh $host "rescan-scsi-bus.sh" > /dev/null
		ssh $host "multipath -F" > /dev/null
		ssh $host "multipath" > /dev/null
		hd=$( indexof $host )
	#	indexof "$host"
	#	echo $?
	#	hd=$?
	#	echo $hd
	# use list of mapping volumes based on name,pool_name and wwn - xcli.py vol_list -f name,pool_name,wwn
	# for each volume checkon the host the attached mpath using the wwn
		for dm in `ssh $host multipath -ll |grep -i $system_serial_hex |cut -f2 -d"-"|cut -f1 -d" "|sort -n`;do  
			echo "sd=sd$sd,host=hd$hd,lun=/dev/dm-$dm,openflags=(o_direct,o_sync,fsync),size=$vdbench_vol_size""g,threads=10,hitarea=170m" >> /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
			((sd++))
		done
	done
	echo "rd=default,xfersize=8k,iorate=max,elapsed=10m,interval=10,openflags=o_direct,hitarea=400m,pause=1m" >> /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
	echo "#rd=prealloc,sd=*,elapsed=1000h,interval=10,rdpct=0,openflags=o_direct,iorate=max,xfersize=256K,seekpct=0,maxdata=1,threads=1,pause=20m" >> /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
	echo "#rd=warmup,sd=*,elapsed=20m,interval=10,openflags=o_direct,iorate=max,xfersize=1m,rhpct=100,whpct=100" >> /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
	echo "rd=Read_Miss_8k_FFR,sd=*,elapsed=30m,iorate=300000,xfersize=8k,rdpct=100,rhpct=0" >> /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
	echo "rd=seq_read,sd=*,elapsed=1000h,interval=10,openflags=o_direct,iorate=max,xfersize=256k,rdpct=100,seekpct=0,maxdata=1,threads=1,pause=20m" >> /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
	echo "rd=Read_miss_8k_noFFR,sd=*,elapsed=30m,iorate=300000,xfersize=8k,rdpct=100,rhpct=0" >> /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
else
	echo "[INFO] Not running vdbench config creation"
fi
echo "[INFO} vdbench config file was created: /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output"
exit
