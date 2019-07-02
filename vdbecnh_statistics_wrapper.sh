#!/bin/sh
#
# This script get as input system_name, vdbecnh config file, and protocol iSCSi/FC.
# It then calls script "vdbecnh_statistics_top1.sh" which start collecting performance statistcis. Then it starts the provided vdbecnh workload.
# Once the workload completes it stops the "vdbecnh_statistics_top1.sh" script.
#
#system_name="ba-pod-44"
if [ $# != 3 ];then
	echo "sample: $0 system_name vdbench_config_file interfcae_protocol"
	exit 1
else
	system_name=$1
	vdbench_cfg=$2
	interface=`echo $3|awk '{print tolower($1)}'`
	echo "test parms are: "$@
	echo "press enter to continue"
	read nu
fi
date=`date +%y%m%d`
vdbench_output=${vdbench_cfg}_${date}
echo $vdbench_output
echo "start - building testbed"
#./Host_$interface_setup_v3.sh
echo "end - building testbed"
#sleep 60
echo "start - CPU collection"
./vdbecnh_statistics_top1.sh $system_name $vdbench_cfg $interface &
#sleep 10
echo "start - $interface vdbench"
cd /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/
pwd
if `egrep -i "dataset_size" ${vdbench_cfg} > /dev/null`;then
	./src/goVdbench.py $vdbench_cfg /root/results
else
	./bin/vdbench -f $vdbench_cfg -o /root/results/$vdbench_output
fi
echo "end - $interface vdbench"
sleep 10
ssh $system_name "rm -f /local/scratch/${vdbench_cfg}_${interface}_top_run"
echo "end - CPU collection"
exit 0