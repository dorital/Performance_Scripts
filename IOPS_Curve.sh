#!/bin/sh
#
# this script creates vol_copy for all volumes 
#
#
function max_workload {
	echo "start - max worklaod"
	cd /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/
	pwd
	./src/goVdbench.py $vdbench_cfg /root/results
#	echo "$vdbench_cfg /root/results"
	#
	sleep 10
	# checking if test output dir is avaialble under /root/results. Once it is detected break from the loop
	for i in `ls -t /root/results/`; do 
		echo $i |grep $vdbench_cfg > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			test_folder="/root/results/${i}"
			break
		fi
	done
	test_folder=`ls -d ${test_folder}/*/`
	echo "Test Folder: $test_folder"
	test_name=`echo ${test_folder} | awk -F"/" '{print $(NF-1)}' | sed 's/_000//'`
	echo "Test Name: ${test_name}"
#	rd_name=`cat ${test_folder}totals.html | grep -i starting | tail -1 | awk -F";" '{print $1}' | awk -F"=" '{print $3}'`
#	echo "RD Name: ${rd_name}"
#	max_iops=`cat ${test_folder}totals.html | grep -i "avg_2" | tail -1 | awk '{print $3}'`
#	echo "Test IOPS max: $max_iops"
}
function iops_curve {
# for each rd in the vdbench output find the max_iops and calculate the curve based on number of samples
for rd_name in `cat ${test_folder}totals.html | grep -i starting | awk -F";" '{print $1}' | awk -F"=" '{print $3}'`;do
	echo $rd_name
# finding the max_iops and making it a round number"	
	max_iops=`sed -n "/RD=${rd_name}/,/Starting/p" ${test_folder}/totals.html | grep avg_2 | awk '{print $3}' |awk -F"." '{print $1}'`
#	max_iops=`echo "$max_iops/1"|bc`
	echo $max_iops
# calculating the curve samples
	curve=`echo "${max_iops}/${samples}"|bc`
	echo $curve
	iorate="(${curve}-${max_iops},${curve})"
	echo $iorate
	cd /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/
#	grep default $vdbench_cfg
	grep ${rd_name} $vdbench_cfg
#	sed -i "/\<${test_name}\>/,/]/s/max/${iorate}/" $vdbench_cfg
# Add iorate iops curve statement for each rd 
	sed -i "/\<${test_name}\>/,/]/s/${rd_name}/${rd_name},iorate=${iorate}/" $vdbench_cfg
#	grep default $vdbench_cfg
	grep ${rd_name} $vdbench_cfg
	#	sed -i "/\<${test_name}\>/,/]/s/${iorate}/max/" $vdbench_cfg
#	sed -i "/\<${test_name}\>/,/]/s/${rd_name},iorate=${iorate}/${rd_name}/" $vdbench_cfg
#	grep default $vdbench_cfg
#	grep ${rd_name} $vdbench_cfg
done
echo "curve is ready?"
read nu
./src/goVdbench.py $vdbench_cfg /root/results
#echo " dbench.py $vdbench_cfg /root/results"
}

if [ $# != 2 ];then
	echo "sample: $0 vdbench_cfg_file #_of_samples"
	exit
fi
vdbench_cfg=$1
#max_iops=$3
samples=$2
echo "test parms are: "$@
echo "press enter to continue"
read nu
max_workload
#echo "max completed ok?"
#read nu
iops_curve

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
