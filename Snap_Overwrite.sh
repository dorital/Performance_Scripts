#this script creates vol_copy for all volumes 
#!/bin/sh

# General Script Setup
to_clean_system="no"
to_do_fccon="no"
to_setup_system="yes"
to_snap_and_map="yes"
to_create_vdbench="yes"
is_it_iSCSI="no"
hostlist=(rmhost7 rmhost8)

function system_setup {
echo "[INFO] Start system $system_name setup"
echo "[INFO] Start - pool creation"
pool_size=`echo "$active_dataset/0.9"|bc`
ssh $system_name xcli.py pool_create pool=$pool_name size=$pool_size snapshot_size=0 -y 1>/dev/null
echo "[INFO] End - pool creation"
#
echo "[INFO] Start - volume creation"
for vol in $(seq 1 $vol_number);do
   ssh $system_name xcli.py vol_create pool=$pool_name size=$vol_size vol=perf_${pool_name}_${vol} 1>/dev/null
done
echo "[INFO] End - volume creation"
#
vol_map=1
for host in "${hostlist[@]}";do
	echo "[INFO] Start - host definition $host using $interface"
	ssh $system_name xcli.py host_define host=$host 1>/dev/null
	host_fc_wwpn=`ssh $host cat /sys/class/fc_host/host*/port_name|cut -f2 -d "x"`
	for fc_wwpn in $host_fc_wwpn;do
	# Adding hosts wwpn on A9K system
		echo $fc_wwpn
		ssh $system_name xcli.py host_add_port host=$host fcaddress=$fc_wwpn 1>/dev/null
	done
	echo "[INFO] End - host definition $host"
#    for vol in $(seq $start_count $end_count);do
	echo "[INFO] Start - host cleaning on $host"
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
	echo "[INFO] Start - volume mapping host $host"
    for lunid in $(seq 1 $host_mapping);do
   	   ssh $system_name xcli.py map_vol host=$host lun=$lunid vol=perf_${pool_name}_${vol_map} 1>/dev/null
	   ((vol_map++))
	done   
	echo "[INFO] End - volume mapping host $host"
	#
	ssh $host rescan-scsi-bus.sh > /dev/null
#	ssh $host multipath -F > /dev/null
echo "[INFO] End system $system_name $interface setup"
done
}

### main ###
if [ $# != 2 ];then
	echo "sample: $0 system_name pool_name"
	exit
fi
system_name=$1
pool_name=$2

echo "Script input parms are: "$@
echo -e "press enter to continue"
read nu

### main ###
echo "[INFO] start - increasing pool and snap size"
#pool_name=`ssh $system_name xcli.py pool_list -z | awk '{print $1}'`
pool_size=`ssh $system_name xcli.py pool_list pool=$pool_name -z | awk '{print $2}'`
pool_new_size=`echo "$pool_size/0.4"|bc`
pool_new_snapsize=`echo "$pool_size/0.9"|bc`
ssh $system_name xcli.py pool_resize pool=$pool_name size=$pool_new_size snapshot_size=$pool_new_snapsize -y 1> /dev/null
echo "[INFO] end - increasing pool and snap size"
echo "[INFO] start - creating cg and adding all volumes to it"
ssh $system_name xcli.py cg_create pool=$pool_name cg=${pool_name}_cg
for vol in `ssh $system_name xcli.py vol_list pool=$pool_name -z | awk '{print $1}'`;do
   ssh $system_name xcli.py cg_add_vol cg=${pool_name}_cg vol=$vol 1>/dev/null
done
echo "[INFO] end - creating cg and adding all volumes to it"
echo "[INFO] - waiting 10 sec"
sleep 10
echo -e "nu?"
read nu
echo "[INFO] start - creating cg snap group"
ssh $system_name xcli.py cg_snapshots_create cg=${pool_name}_cg 1>/dev/null
snap_group=`ssh $system_name xcli.py -z snap_group_list cg=${pool_name}_cg|awk '{print $1}'`
echo "[INFO] end - creating cg snap grooup"
echo "[INFO] waiting 60 sec"
sleep 60
echo "nu?"
read nu


# make snap r/w
ssh $system_name xcli.py snap_group_unlock snap_group=$snap_group
#map the new snap voluems
host_number=`echo ${#hostlist[@]}`
snap_number=`xcli.py vol_list -z cg=${pool_name}_cg |grep -i snapshot|wc -l`
snap_mapping=`echo "$snap_number/$host_number"|bc`

for host in "${hostlist[@]}";do
	echo "[INFO] Start - snap volume mapping host $host"
	
	for snap in `xcli.py vol_list -z cg=${pool_name}_cg |grep -i snapshot`;do
   	   ssh $system_name xcli.py map_vol host=$host lun=$lunid vol=perf_${pool_name}_${vol_map} 1>/dev/null
	   ((vol_map++))
	done   
	echo "[INFO] End - snap volume mapping host $host"
	#
	ssh $host rescan-scsi-bus.sh > /dev/null
#	ssh $host multipath -F > /dev/null
echo "[INFO] End system $system_name $interface setup"
done

# rescan the hosts

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
echo "[INFO} vdbench config file was created: /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_sd_output"




src/goVdbench.py vdbench.cfg.$vdbench_config /root/results &







for snap_group in `ssh $system_name xcli.py snap_group_list -z | awk '{print $1}'`;do
   echo "start - mapping and reading snap group: " $snap_group
#   ssh $system_name xcli.py snap_group_unlock snap_group=$snap_group > /dev/null
   for vol in `ssh $system_name xcli.py mapping_list -z|awk '{print $2}'`;do
      host=`ssh $system_name xcli.py vol_mapping_list vol=$vol -z | awk '{print $1}'`
      lunid=`ssh $system_name xcli.py vol_mapping_list vol=$vol -z | awk '{print $3}'`
	  ssh $system_name xcli.py unmap_vol vol=$vol host=$host -y
#          echo "nu?"
#          read nu
	  if `echo $vol|grep snap > /dev/null`;then
	     source_vol=`echo $vol | cut -d"." -f3`
             echo $source_vol
             echo $snap_group"."$source_vol
#             echo "nu?"
#             read nu
	    ssh $system_name xcli.py map_vol host=$host lun=$lunid vol=$snap_group"."$source_vol   	 
	  else
             echo $snap_group"."$vol
#             echo "nu?"
#             read nu
             ssh $system_name xcli.py map_vol host=$host lun=$lunid vol=$snap_group"."$vol
	  fi
   done
   echo "nu?"
   read nu
   src/goVdbench.py vdbench.cfg.$system_name_partial_icp_read /root/results
   echo "end - mapping and reading snap group: " $snap_group
done
exit

exit


