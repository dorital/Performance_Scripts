#this script creates vol_copy for all volumes 
#!/bin/sh

### main ###
if [ $# != 2 ];then
	echo "sample: $0 system_name number_of_snaps_cycles"
	exit
fi
system_name=$1
number_of_snaps_cycles=$2

echo "Script input parms are: "$@
echo -e "press enter to continue"
read nu

### main ###
echo "[INFO] - Ensure desired IO is running on system $system_name"
#/root/dorontal/xiv_rtc_performance/benchmarks/vdbench/src/goVdbench.py vdbench.cfg.$system_name_partial_icp_prealloc /root/results
echo "[INFO] start - increasing pool and snap size"
pool_name=`ssh $system_name xcli.py pool_list -z | awk '{print $1}'`
pool_size=`ssh $system_name xcli.py pool_list pool=$pool_name -z | awk '{print $2}'`
pool_new_size=`echo "$pool_size/0.4"|bc`
pool_new_snapsize=`echo "$pool_size/0.9"|bc`
ssh $system_name xcli.py pool_resize pool=$pool_name size=$pool_new_size snapshot_size=$pool_new_snapsize -y 1> /dev/null
echo "[INFO] end - increasing pool and snap size"
echo "[INFO] start - creating cg and adding all volumes to it"
ssh $system_name xcli.py cg_create pool=$pool_name cg=${pool_name}_cg
for vol in `ssh $system_name xcli.py vol_list -z | awk '{print $1}'`;do
   ssh $system_name xcli.py cg_add_vol cg=${pool_name}_cg vol=$vol 1>/dev/null
done
echo "[INFO] end - creating cg and adding all volumes to it"
echo "[INFO] - waiting 10 sec"
sleep 10
echo -e "nu?"
read nu
for i in $(seq 1 $number_of_snaps_cycles);do
   echo "[INFO] start - creating snapshots cycle #$i"
   ssh $system_name xcli.py cg_snapshots_create cg=${pool_name}_cg 1>/dev/null
   snap_group=`ssh $system_name xcli.py -z snap_group_list|awk '{print $1}'`
   echo "[INFO] end - creating snapshots cycle #$i"
   echo "[INFO] waiting 60 sec"
   sleep 60
   echo "[INFO] start - deleting snapshots cycle #$i"
   ssh $system_name xcli.py snap_group_delete snap_group=$snap_group -y 1> /dev/null
   echo "[INFO] stop - deleting snapshots cycle #$i"   
done
exit

echo "start reading snapshots?"
read nu
echo "waiting 600 sec"
sleep 600
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


