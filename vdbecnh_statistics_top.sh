#!/bin/sh
#
# This script is called by the "vdbecnh_statistics_wrapper1.sh" script which provide it as input system_name, vdbecnh config file, and protocol type iSCSI/FC
# Then it creates perf record for an interfcae pid and a drn pid using the vdbench config file naming. last it collects top output for the interface pids and drn pids.
#
#system_name='ba-pod-44'
system_name=$1
vdbench_cfg=$2
interface=$3
if [ "$interface" == "iscsi" ]; then
	interface_pid=`ssh $system_name ps -ef|grep xis|grep xiv|awk '{print $2}'`
	interface_pid=`echo $interface_pid|sed 's/ /,/g'`
else 
	interface_pid=`ssh $system_name ps -ef|grep fc-port|grep xiv|awk '{print $2}'`
	interface_pid=`echo $interface_pid|sed 's/ /,/g'`
fi
inode_pid=`ssh $system_name ps -ef|grep i_node|grep xiv|awk '{print $2}'`
worker_pid=`ssh $system_name top -b -n1 -H|gawk '/\<worker\>/ {print$1}'`
worker_pid=`echo $worker_pid|sed 's/ /,/g'`
echo "the ${interface} PID's are: "$interface_pid
ssh $system_name "rm -f /local/scratch/${vdbench_cfg}_${interface}_top_output"
ssh $system_name "rm -f /local/scratch/${vdbench_cfg}_${interface}_top_run"
ssh $system_name "touch /local/scratch/${vdbench_cfg}_${interface}_top_run"
#ssh $system_name "echo 1 > /local/scratch/iscsi_top_run"
#ssh $system_name "cat /local/scratch/iscsi_top_run"
sleep 60
# doing perf record
perf_interface_pid=`echo $interface_pid | awk -F"," '{print $1}'`
perf_worker_pid=`echo $worker_pid | awk -F"," '{print $1}'`
echo "performing perf record for ${interface} thread"
ssh $system_name "perf record -g --call-graph dwarf -o /local/scratch/perf_record_${vdbench_cfg}_${interface} -t $perf_interface_pid sleep 5" > /dev/null
echo "performing perf record for inode thread"
ssh $system_name "perf record -g --call-graph dwarf -o /local/scratch/perf_record_${vdbench_cfg}_${interface}_inode -t $perf_worker_pid sleep 5" > /dev/null
# capturing top statistics
while `ssh $system_name test -e "/local/scratch/${vdbench_cfg}_${interface}_top_run"`; do
#while [ `ssh $system_name "cat /local/scratch/iscsi_top_run"` == 1 ];do
	ssh $system_name "top -b -n3 -p$interface_pid >> /local/scratch/${vdbench_cfg}_${interface}_top_output"
	ssh $system_name "echo inode worker CPU >> /local/scratch/${vdbench_cfg}_${interface}_top_output"
	ssh $system_name "top -b -n3 -H -p$inode_pid|grep worker >> /local/scratch/${vdbench_cfg}_${interface}_top_output"
#	ssh $system_name "top -b -n3 -H -p$worker_pid >> /local/scratch/iscsi_top_output"
	sleep 120
done
exit 0