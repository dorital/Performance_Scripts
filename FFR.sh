#this script creates vol_copy for all volumes 
#!/bin/sh
### main ###
#
if [ $# != 3 ];then
	echo "sample: $0 system_name vdbench_cfg_file max_iops"
	exit
fi
system_name=$1
vdbench_cfg=$2
max_iops=$3
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
for ((i=20;i<=100;i+=20));do
#for i in {20..100..20};do
	iops=`echo "$max_iops*$i/100"|bc`
	echo "start - fast full recovery for curve $i iops $iops"
	ssh $system_name xcli.py conf_set path=misc.internal.drn_config.enable_setting_offline value=yes -Ud
	ssh $system_name xcli.py data_reduction_set_offline -Ud -y 
# Normal FFR
	ssh $system_name xcli.py -Ud data_reduction_recovery_flags_set recovery_1=20000000 recovery_2=18000000
# Force FFR
#	ssh $system_name xcli.py -Ud data_reduction_recovery_flags_set recovery_1=A0000000 recovery_2=18000000
# MIFR
#	ssh $system_name xcli.py -Ud data_reduction_recovery_flags_set recovery_1=10000000 recovery_2=18000000
# Force MIFR
#	ssh $system_name xcli.py -Ud data_reduction_recovery_flags_set recovery_1=90000000 recovery_2=18000000
	sleep 60
	while [ `ssh $system_name xcli.py data_reduction_recovery_status -z|awk '{print$3}'` != 0 ]
		do
		echo "Recovery still running `ssh $system_name xcli.py data_reduction_recovery_status -z|awk '{print$3}'`"
		sleep 60
	done
	ssh $system_name xcli.py data_reduction_resume_online -Ud
	echo "end - fast full recovery for curve $i iops $iops"
	sleep 30
#	echo "nu?"
#	read nu
	sed -i "s/iops_input/$iops/" $vdbench_cfg
#	echo "nu?"
#	read nu
	echo "start - FFR vdbench curve $i iops=$iops"
	grep default $vdbench_cfg
	/root/dorontal/xiv_rtc_performance/benchmarks/vdbench/bin/vdbench -f /root/dorontal/xiv_rtc_performance/benchmarks/vdbench/$vdbench_cfg -o /root/results/$vdbench_output"_curve_"$i
	sed -i "s/$iops/iops_input/" $vdbench_cfg 
	echo "end - FFR vdbench curve $i iops=$iops"
#	echo "nu?"
#	read nu
	sleep 600
done
exit
