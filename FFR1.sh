#this script creates vol_copy for all volumes 
#!/bin/sh
### main ###
#
if [ $# != 2 ];then
	echo "sample: $0 system_name vdbench_cfg_file"
	exit
fi
system_name=$1
vdbench_cfg=$2
echo "test parms are: "$@
echo "press enter to continue"
read nu
#
#system_name='ba-pod-44'
#max_iops=448000
#vdbench_cfg="FFR_vdbench_Read_Miss_8k_32TB"
date=`date +%F-%H%M`
vdbench_output=$vdbench_cfg"_"$date
echo $vdbench_output

cd /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/
echo "start - fast full recovery"
ssh $system_name xcli.py conf_set path=misc.internal.drn_config.enable_setting_offline value=yes -Ud
ssh $system_name xcli.py data_reduction_set_offline -Ud -y 
ssh $system_name xcli.py -Ud data_reduction_recovery_flags_set recovery_1=20000000 recovery_2=18000000
ssh $system_name xcli.py data_reduction_recovery_start -Ud
sleep 60
while [ `ssh $system_name xcli.py data_reduction_recovery_status -z|awk '{print$3}'` != 0 ]
	do
	echo "Recovery still running `ssh $system_name xcli.py data_reduction_recovery_status -z|awk '{print$3}'`"
	sleep 60
done
ssh $system_name xcli.py data_reduction_resume_online -Ud
echo "end - fast full recovery"
sleep 30
#echo "nu?"
#read nu
echo "start - FFR vdbench"
/usr/global/scripts/dori/git/perfScript/Utilities/dd_output_6k.sh &
#/root/dorontal/xiv_rtc_performance/benchmarks/vdbench/bin/vdbench bin/vdbench -f ba-pod-44_fc_24000GB_FFR_RM4K -o /root/results/ba-pod-44_fc_24000GB_FFR_RM4K_0909 &
/root/dorontal/xiv_rtc_performance/benchmarks/vdbench/bin/vdbench -f /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_cfg -o /root/results/$vdbench_output
/usr/global/scripts/dori/git/perfScript/Utilities/dd_output_6k.sh &
/root/dorontal/xiv_rtc_performance/benchmarks/vdbench/bin/vdbench -f /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_cfg -o /root/results/$vdbench_output

echo "end - FFR vdbench"
exit


	
	
	
	
	
	
ssh $system_name xcli.py cg_create pool=$pool_name cg=cherry_cg
for vol in `ssh $system_name xcli.py mapping_list -z|awk '{print $2}'`;do
   ssh $system_name xcli.py cg_add_vol cg=cherry_cg vol=$vol > /dev/null
done
echo "end - creating cg and adding all volumes to it"
#
cd /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/
src/goVdbench.py vdbench.cfg.gen4d-41_vol_copy /root/results &
cd /usr/global/scripts/dori
echo "wait 10 min"
sleep 600
#
for i in {1..5};do
	echo "start - creating vol snapshots cycle #$i"
    ssh $system_name xcli.py cg_snapshots_create cg=cherry_cg
	snap_group=`ssh $system_name xcli.py -z snap_group_list|awk '{print $1}'`
	echo "end - creating target vol copies"
#
	echo "start - creating snapshots vol_copy cycle #$i"
	for vol in `ssh $system_name xcli.py mapping_list -z|awk '{print $2}'`;do
		size=`ssh $system_name xcli.py vol_list vol=$vol -z | awk '{print $2}'`
		echo "start - vol copy create #$i $vol"
		ssh $system_name xcli.py vol_create pool=$pool_name vol=$vol"_copy"$i size=$size > /dev/null
		echo "end - vol copy create #$i $vol"
		echo "start - snap $snap_group copy to vol copy #$i $vol"
		ssh $system_name xcli.py vol_copy vol_src=$snap_group"."$vol vol_trg=$vol"_copy"$i -y > /dev/null 
		echo "end - snap $snap_group copy to vol copy #$i $vol"
	done
	echo "end - creating snapshots vol_copy cycle #$i"
#
	echo "start- delete snap group $snap_group"
	ssh $system_name xcli.py snap_group_delete snap_group=$snap_group -y > /dev/null 
	echo "end - delete snap group $snap_group"
#
	echo "waiting 1800 sec"
	sleep 1800
#	echo "start - vdbecnh 70_30"
#	cd /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/
#	src/goVdbench.py vdbench.cfg.gen4d-41_vol_copy /root/results 
#	cd /usr/global/scripts/dori
#	echo "end - vdbecnh 70_30"
#
    echo "start - deleting vol copies $i"
	for vol in `ssh $system_name xcli.py vol_list -z |grep copy | awk '{print $1}'`
		do
		ssh $system_name xcli.py vol_delete vol=$vol -y > /dev/null
	done
    echo "end - deleting vol copies $i"
#
	echo "waiting 900 sec"
	sleep 900
	while [ `ssh $system_name grep UnmapSegmentCount /tmp/RACE_counters.log|tail -1|cut -f4 -d","|cut -f2 -d":"` != 0 ]
		do
		echo "unmap still running `ssh $system_name grep UnmapSegmentCount /tmp/RACE_counters.log|tail -1|cut -f4 -d","`"
		sleep 300
	done
done
exit
