#!/bin/sh
#
# this script uses dd to copy volumes from source system to target system.
# It scans the mapped volumes on both source and target system and creates an dd output file to execute the copy
#
# General Script Setup
hostlist=(mc022 mc023 mc036 mc063 mc062 mc064)
#
function indexof {
i=0;
while [ "$i" -lt "${#hostlist[@]}" ] && [ "${hostlist[$i]}" != "$1" ]; do
	((i++));
done;
echo $i;
#return $i
}
#

if [ $# != 2 ];then
	echo "sample: $0 source_system_name target_system_name"
	exit
fi
source_system_name=$1
target_system_name=$2
echo "Script input parms are: "$@
echo "Script internal parms are:"
echo "Source system is:" $source_system_name
echo "Target system is:" $target_system_name
echo -e "host list:\t"${hostlist[@]}
echo -e "press enter to continue"
read nu
#
source_system_serial=`ssh $source_system_name xcli.py config_get |grep system_id |awk '{print $2}'`
source_system_serial_hex=`echo "obase=16; $source_system_serial"|bc`
target_system_serial=`ssh $target_system_name xcli.py config_get |grep system_id |awk '{print $2}'`
target_system_serial_hex=`echo "obase=16; $target_system_serial"|bc`
#echo "source system hex serial:" $source_system_serial_hex
#echo "target system hex serial:" $target_system_serial_hex
#

echo "# This file is the output of dd_setup.sh script" > dd_output.sh
echo date >> dd_output.sh
for host in "${hostlist[@]}";do 
	counter=1
	echo "[INFO] hostname: $host"
#	number_dm=`ssh $host multipath -ll |grep -i $source_system_serial_hex |wc -l`
#	hd=$( indexof $host )
	ssh $host multipath -F > /dev/null
	ssh $host multipath > /dev/null
	for source_dm in `ssh $host multipath -ll |grep -i $source_system_serial_hex | awk '{print $3}'`;do
	#	$(seq 1 $number_dm); do
		source_dd[$counter]=$source_dm
		((counter++))
	done
	counter=1
	for target_dm in `ssh $host multipath -ll |grep -i $target_system_serial_hex|awk '{print $3}'`;do
		target_dd[$counter]=$target_dm
		((counter++))
	done
	echo "source system $source_system_name, hex serial $source_system_serial_hex, source dm:" ${source_dd[@]} "number of dm:" ${#source_dd[@]}
	echo "target system $target_system_name, hex serial $target_system_serial_hex, source dm:" ${target_dd[@]} "number of dm:" ${#target_dd[@]}
	for i in $(seq 1 ${#source_dd[@]});do
		echo "ssh $host 'dd if=/dev/${source_dd[$i]} of=/dev/${target_dd[$i]} bs=256K &'" >> dd_output.sh
#		ssh $host "dd if=/dev/${source_dd[$i]} of=/dev/${target_dd[$i]} bs=256K &"
	done
done
exit

