#this script enables you to setup a Linux host with its iso image, blast and HAK
#!/bin/sh
#
#
#
function system_clean {
echo "start - vol unmap"
unmap_list=`ssh $system_name xcli.py -z mapping_list|awk -F " " '{print $2}'`
for unmap_vol in $unmap_list;do
   unmap_host=`ssh $system_name xcli.py vol_mapping_list vol=$unmap_vol -z | awk '{print $1}'`
   ssh $system_name xcli.py unmap_vol vol=$unmap_vol host=$unmap_host -y > /dev/null
done
echo "end - vol unmap"
#echo "nu?"
#read nu
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
host_clean=`ssh $system_name xcli.py -z host_list|cut -f1 -d" "`
for delete_host in $host_clean;do
    ssh $system_name xcli.py host_delete host=$delete_host -y > /dev/null
done
echo "end - host cleaning"
#
}

function system_setup {
echo "setup $system_name iSCSI interfaces"
echo $system_name"_iscsi"
ssh $system_name /local/scratch/$system_name"_iscsi.sh"
echo "$system_name iSCSI interfaces:"
ssh $system_name xcli.py ipinterface_list | grep -i iscsi
#
echo "start - pool creation"
ssh $system_name xcli.py pool_create pool=$pool_name size=$pool_size snapshot_size=0 -y > /dev/null
echo "end - pool creation"
echo "start - volume creation"
for vol in $(seq 1 $vol_number);do
   ssh $system_name xcli.py vol_create pool=$pool_name size=$vol_size vol=iscsi_$vol > /dev/null
done
echo "end - volume creation"
for host in "${hostlist[@]}";do
	# get host IQN
	echo "Defining and mapping host $host via iSCSI"
	host_iqn=`ssh $host cat /etc/iscsi/initiatorname.iscsi|cut -d "=" -f2`
	# define host on A9K system with identified IQN
	ssh $system_name xcli.py host_define host=$host > /dev/null
	ssh $system_name xcli.py host_add_port host=$host iscsi_name=$host_iqn > /dev/null
    # mapping volumes to host
#    for vol in $(seq $start_count $end_count);do
    for lunid in $(seq 1 $host_mapping);do
#	   ssh $system_name xcli.py map_vol host=$host lun=$vol vol=iscsi_$vol > /dev/null
   	   ssh $system_name xcli.py map_vol host=$host lun=$lunid vol=iscsi_$vol_map > /dev/null
	   ((vol_map++))
#	   echo $vol_map
	done   
done
#
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
# old host list method
#host_list='mc028 mc029 mc031 mc032 mc034 mc035 mc036 mc051 mc052 mc069'
#
# all host with iSCSI 
#hostlist=(mc028 mc029 mc031 mc032 mc034 mc035 mc036 mc051 mc052 mc069)
#
# host with both iSCSI and FC connectivity
hostlist=( mc034 mc035 mc036 mc051 mc052 mc069)

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
# old input method
#system_name=ba-pod-44
#active_dataset=32000
#vol_number=120
# main varibales 
# pool varibales
pool_name='pool_iSCSI' 
pool_size=`echo "$active_dataset/0.9"|bc`
# volume varibales
vol_size=`echo "$active_dataset/$vol_number"|bc`
vdbench_vol_size=`echo "$vol_size/1.1"|bc`
# host varibales
host_number=`echo ${#hostlist[@]}`
host_mapping=`echo "$vol_number/$host_number"|bc`
# general varibales
start_count=1
end_count=$host_mapping
vol_map=1
# system varibales
system_serial=`ssh $system_name xcli.py config_get |grep system_id |awk '{print $2}'`
system_serial_hex=`echo "obase=16; $system_serial"|bc`
#
#
# get A9K target ip
#target_ip=`ssh $system_name xcli.py ipinterface_list |grep -m 1 -i iscsi|awk -F " " '{print $3}'`
target_subnet1_ip=`ssh $system_name xcli.py ipinterface_list |grep -m 1 -i 172.18.5 |awk -F " " '{print $3}'`
target_subnet2_ip=`ssh $system_name xcli.py ipinterface_list |grep -m 1 -i 172.18.6 |awk -F " " '{print $3}'`
# get A9K IQN
a9k_iqn=`ssh $system_name xcli.py config_get |grep iscsi_name|awk -F " " '{print $2}'`
echo "cleaning the system"
#system_clean
echo "system setup"
#system_setup
#
# Hosts iSCSI setup - run on host_list
# 
#for host in $host_list;do
for host in "${hostlist[@]}";do
	echo $host
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
	ssh $host traceroute -4 --mtu $target_subnet1_ip|grep 9000 > /dev/null
	if [[ $? -ne 0 ]]; then
	   echo "MTU is not 9000 on host $host subnet $target_subnet1_ip"
	   exit 
	fi
	ssh $host traceroute -4 --mtu $target_subnet2_ip|grep 9000 > /dev/null
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
	ssh $host rescan-scsi-bus.sh -r -f > /dev/null
	ssh $host multipath -F > /dev/null
	ssh $host multipath > /dev/null
	echo "End -  Connecting host $host to iSCSI and luns"
done
sd=0
vdbench_sd_output="iSCSI_"$system_name"_AD_"$active_dataset"_vdbench_sd_output"
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
for host in "${hostlist[@]}";do 
	echo "$host"
	ssh $host rescan-scsi-bus.sh -f > /dev/null
	ssh $host multipath -F > /dev/null
	ssh $host multipath > /dev/null
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
