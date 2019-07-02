#!/bin/sh
#
# this script gets a system, list of FC host, active dataset and volume number and cleans the system, setup the environemnt and creates basic vdbench output
#
#
function system_clean {
#
echo "start - vol unmap"
unmap_list=`ssh $system_name xcli.py -z mapping_list|awk -F " " '{print $2}'`
for unmap_vol in $unmap_list;do
   unmap_host=`ssh $system_name xcli.py vol_mapping_list vol=$unmap_vol -z | awk '{print $1}'`
   ssh $system_name xcli.py unmap_vol vol=$unmap_vol host=$unmap_host -y > /dev/null
done
echo "end - vol unmap"
#
echo "start - pool cleaning"
pool_list=`ssh $system_name xcli.py -z pool_list|cut -f1 -d" "`
for pool in $pool_list;do
   vol_list=`ssh $system_name xcli.py -z vol_list pool=$pool |cut -f1 -d" "`
   for vol in $vol_list;do
#      ssh $system_name xcli.py unmap_vol -y vol=$vol
      ssh $system_name xcli.py vol_delete -y vol=$vol > /dev/null
   done
   ssh $system_name xcli.py pool_delete -y pool=$pool > /dev/null
done
echo "end - pool cleaning"
#
echo "start - host cleaning"
for host in "${hostlist[@]}";do
	echo $host
    ssh $system_name xcli.py host_delete host=$host -y > /dev/null
	host_dev_list=`ssh $host multipath -ll|grep ":"|awk '{print $2}'`
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
echo "end - host cleaning"
#
}

function fccon {
echo "start - deleting all exiting zones for ${system_name}"
ssh stcon "/opt/FCCon/fcconnect.pl -op DisConnectAll -stor ${system_name}"
echo "end - deleting all exiting zones for ${system_name}"
echo "start - creating new zones  for ${system_name}"
fccon_hosts=""
for host in "${hostlist[@]}";do 
	fccon_hosts="${fccon_hosts} -host ${host}"
	echo $fccon_hosts
done
ssh stcon "/opt/FCCon/fcconnect.pl -op Connect -stor ${system_name} ${fccon_hosts}"
echo "end - creating new zones  for ${system_name}"
}

function system_setup {
echo "start - pool creation"
pool_name='pool_perf' 
pool_size=`echo "$active_dataset/0.9"|bc`
ssh $system_name xcli.py pool_create pool=$pool_name size=$pool_size snapshot_size=0 -y 1>/dev/null
echo "end - pool creation"
#
echo "start - volume creation"
for vol in $(seq 1 $vol_number);do
   ssh $system_name xcli.py vol_create pool=$pool_name size=$vol_size vol=perf_$vol 1>/dev/null
done
echo "end - volume creation"
#
for host in "${hostlist[@]}";do
	echo "start - host definition $host"
	ssh $system_name xcli.py host_define host=$host 1>/dev/null
	# command to verify connectivity
	host_fc_wwpn=`ssh $host cat /sys/class/fc_host/host*/port_name|cut -f2 -d "x"`
	for fc_wwpn in $host_fc_wwpn;do
	# define host on A9K system with identified wwpn
	echo $fc_wwpn
		ssh $system_name xcli.py host_add_port host=$host fcaddress=$fc_wwpn 1>/dev/null
	done
	echo "end - host definition $host"
	#
    # mapping volumes to host
#    for vol in $(seq $start_count $end_count);do
	echo "start - volume mapping host $host"
    for lunid in $(seq 1 $host_mapping);do
   	   ssh $system_name xcli.py map_vol host=$host lun=$lunid vol=perf_$vol_map 1>/dev/null
	   ((vol_map++))
	done   
	echo "end - volume mapping host $host"
	#
	ssh $host rescan-scsi-bus.sh > /dev/null
#	ssh $host multipath -F > /dev/null
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
# general setup info
#host_list='mc028 mc029 mc031 mc032 mc034 mc035 mc036 mc051 mc052 mc069'
hostlist=(mc023 mc022 mc036 mc063 mc062 mc064)
#hostlist=(mc034 mc035 mc036 mc051 mc052 mc069)
#hostlist=(mc028 mc029 mc031 mc032 mc051 mc052 mc069)

if [ $# != 3 ];then
	echo "sample: $0 system_name active_dataset_size_GB vol_number"
	exit
fi
system_name=$1
active_dataset=$2
vol_number=$3
echo "test parms are: "$@
echo "press enter to continue"
read nu
#system_name=ba-pod-44
#active_dataset=32000
#vol_number=120
#
vol_size=`echo "$active_dataset/$vol_number"|bc`
host_number=`echo ${#hostlist[@]}`
host_mapping=`echo "$vol_number/$host_number"|bc`
start_count=1
end_count=$host_mapping
vol_map=1
echo "cleaning the system"
#system_clean
#
echo "system setup"
#fccon
#system_setup
#exit
#
sd=0
vdbench_vol_size=`echo "$vol_size/1.1"|bc`
vdbench_sd_output="FC_"$system_name"_AD_"$active_dataset"_vdbench_sd_output"
rm -f /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
echo "compratio=2.86" > /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
echo "dedupratio=2,dedupunit=8k,dedupsets=5%" >> /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
echo "debug=25" >> /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
echo "hd=default,vdbench=/root/vdbench/bin,user=root,shell=ssh" >> /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
for host in "${hostlist[@]}";do 
	hd=$( indexof $host )
	echo "hd=hd$hd,system=$host" >> /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
done
#
system_serial=`ssh $system_name xcli.py config_get |grep system_id |awk '{print $2}'`
system_serial_hex=`echo "obase=16; $system_serial"|bc`
echo $system_serial_hex
for host in "${hostlist[@]}";do 
	echo "$host"
	ssh $host "rescan-scsi-bus.sh > /dev/null"
	ssh $host "multipath -F > /dev/null"
	ssh $host "multipath > /dev/null"
	hd=$( indexof $host )
#	indexof "$host"
#	echo $?
#	hd=$?
#	echo $hd
	for dm in `ssh $host multipath -ll |grep -i $system_serial_hex |cut -f2 -d"-"|cut -f1 -d" "|sort -n`;do  
		echo "sd=sd$sd,host=hd$hd,lun=/dev/dm-$dm,openflags=(o_direct,o_sync,fsync),size=$vdbench_vol_size""g,threads=10,hitarea=170m" >> /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
		((sd++))
	done
done
echo "rd=default,xfersize=8k,iorate=max,elapsed=10m,interval=10,openflags=o_direct,hitarea=400m,pause=1m" >> /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
echo "rd=prealloc,sd=*,elapsed=1000h,interval=10,rdpct=0,openflags=o_direct,iorate=max,xfersize=256K,seekpct=0,maxdata=1,threads=1,pause=20m" >> /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output
echo "rd=warmup,sd=*,elapsed=20m,interval=10,openflags=o_direct,iorate=max,xfersize=1m,rhpct=100,whpct=100" >> /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output

exit
