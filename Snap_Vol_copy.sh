#!/bin/sh
# 
# This script get as input - system name, vdbecnh config file and number of snap/vol_copy cycles to execute. 
# It assume AD was already allocated.
# It groups all existing volumes in CG
# It executes the provided vdbecnh config file 
# While worklaod is running, it issues cycles of cg_snap and then doing a vol_copy for each snap. (initiate Xcopy).
# Once the vol_copy completes and no more Xcopy it deletes the snaps
# It waits 1 hour and then deletes the vol copies volumes (initiet Unmap)
# 
function check_rc {
	rc=$?
	if [ $rc -ne 0 ];then
		echo "[ERROR]: last operation RC was ${rc}, not ok existing"
		exit 1
	fi
}

if [ $# != 3 ];then
	echo "sample: $0 system_name vdbench_cfg_file snap_cycles"
	exit
fi
system_name=$1
vdbench_cfg=$2
snap_cycles=$3
echo -e "test parms are: "$@
echo -e "press enter to continue"
read nu
#
echo "[INFO] - start pool resize multiply by ${snap_cycles}, snap size multiply by 2"
pool_name=`ssh $system_name xcli.py pool_list -z | awk '{print $1}'`
check_rc
cg_name=${pool_name}_cg
pool_size=`ssh $system_name xcli.py pool_list pool=$pool_name -z | awk '{print $2}'`
check_rc
#pool_new_size=`echo $(($pool_size * $snap_cycles))`
pool_new_size=`echo $(($pool_size * 3))`
#pool_new_snapsize=`echo $(($pool_size * 2))`
pool_new_snapsize=$pool_size
#ssh $system_name xcli.py pool_resize pool=$pool_name size=$pool_new_size snapshot_size=$pool_new_snapsize -y > /dev/null
check_rc
echo "[INFO] - end pool resize multiply by ${snap_cycles}, snap size multiply by 2"
#
echo "[INFO] - start creating cg and adding all volumes to it"
#ssh $system_name xcli.py cg_create pool=$pool_name cg=$cg_name > /dev/null
check_rc
#for vol in `ssh $system_name xcli.py mapping_list -z|awk '{print $2}'`;do
#   ssh $system_name xcli.py cg_add_vol cg=$cg_name vol=$vol > /dev/null
#done
echo "[INFO] - creating cg and adding all volumes to it"
# Modify and Uncomment in case you want the script to run the vdbecnh work as well
###echo "[INFO] - start vdbecnh workload ${$vdbench_cfg}"
###cd /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/
###src/goVdbench.py $vdbench_cfg /root/results &
###cd /usr/global/scripts/dori
###echo "[INFO] vdbecnh worklaod started, waiting 10 min before starting snap/vol_copy cycles"
###sleep 600
#
echo "nu?"
read nu
for i in $(seq 1 $snap_cycles);do
	date
	echo "[INFO] - start creating cg_snapshots cycle #$i"
    ssh $system_name xcli.py cg_snapshots_create cg=$cg_name
	snap_group=`ssh $system_name xcli.py -z snap_group_list|awk '{print $1}'`
	echo "[INFO] - end creating cg_snapshots cycle #$i"
#
	echo "[INFO] - start creating snapshots & vol_copy cycle #$i"
	for vol in `ssh $system_name xcli.py mapping_list -z|awk '{print $2}'`;do
		size=`ssh $system_name xcli.py vol_list vol=$vol -z | awk '{print $2}'`
		echo "[INFO] - start vol copy create #$i $vol"
		ssh $system_name xcli.py vol_create pool=$pool_name vol=$vol"_copy"$i size=$size > /dev/null
		echo "[INFO] - end vol copy create #$i $vol"
		echo "[INFO] - start snap ${snap_group}.${vol} copy to vol copy ${vol}_copy, cycle $i"
		ssh $system_name xcli.py vol_copy vol_src=$snap_group"."$vol vol_trg=$vol"_copy"$i -y > /dev/null 
		echo "[INFO] - end snap ${snap_group}.${vol} copy to vol copy ${vol}_copy, cycle $i"
	done
	echo "[INFO] - end creating snapshots vol_copy cycle #$i"
#
	echo "[INFO] - start delete snap group $snap_group"
	ssh $system_name xcli.py snap_group_delete snap_group=$snap_group -y > /dev/null 
	echo "[INFO] - end delete snap group $snap_group"
#
	echo "[INFO] - waiting 15 min for Xcopy to complete"
	sleep 900
	while [ `ssh $system_name grep "Success" /tmp/RACE_counters.log|tail -1|cut -f1 -d","|cut -f3 -d":"` != 0 ]
		do
		echo "[INFO] - Xcopy still running `ssh $system_name grep "Success" /tmp/RACE_counters.log|tail -1|cut -f1 -d","|cut -f3 -d":"`, waiting 1 min"
		sleep 60
	done
	sleep 60
#	echo "start - vdbecnh 70_30"
#	cd /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/
#	src/goVdbench.py vdbench.cfg.gen4d-41_vol_copy /root/results 
#	cd /usr/global/scripts/dori
#	echo "end - vdbecnh 70_30"
#
	date
    echo "[INFO] - start deleting vol copies $i"
	for vol in `ssh $system_name xcli.py vol_list -z |grep copy | awk '{print $1}'`
		do
		ssh $system_name xcli.py vol_delete vol=$vol -y > /dev/null
	done
    echo "[INFO] - end deleting vol copies $i"
#
	echo "[INFO] - waiting 1 hour for Unmap to complete"
	sleep 3600
	while [ `ssh $system_name grep UnmapSegmentCount /tmp/RACE_counters.log|tail -1|cut -f4 -d","|cut -f2 -d":"` != 0 ]
		do
		echo "[INFO] - Unmap still running `ssh $system_name grep UnmapSegmentCount /tmp/RACE_counters.log|tail -1|cut -f4 -d","`, waiting 1 min"
		sleep 60
	done
	sleep 60
done
exit
