#!/bin/sh
#
# This script gets as input: system_name, RACE_build and if it is master or side branch. 
# it will copy the required RACE code to the specific system and install it. 
#
#
# General Script Setup

function a9k_replace_race {
ssh $system_name tar -xvf /local/scratch/race_xiv.tar.gz
ssh $system_name cp /local/scratch/RACE_sdk/lib/librace.so /local/scratch/librace.so_${race_branch}
#
ssh $system_name xcli.py traces_stop
ssh $system_name parashell.py xbox rw

for module in `ssh $system_name xcli.py -z service_list | grep Reduction | awk '{print $1}'`;do
	moduleNumber=$(echo $module|cut -d: -f3)
	ssh $system_name xcli.py service_phaseout service=$module;
	sleep 10;
	ssh $system_name xcli.py service_list;
	ssh $system_name scp /local/scratch/librace.so_${race_branch} module-$moduleNumber:/xiv/system/data_reduction_node/RACE_sdk/lib/librace.so
	ssh $system_name xcli.py service_phasein service=$module;
	sleep 20;
	ssh $system_name xcli.py service_list;
done
ssh $system_name parashell.py xbox ro
}



### main ###
if [ $# != 3 ];then
	echo "sample: $0 system_name RACE_build/branch_name master/side"
	exit
fi
system_name=$1
race_branch=$2
branch_type=`echo $3|awk '{print tolower($1)}'`

echo "Script input parms are: "$@
echo "Script internal parms are:"
echo -e "press enter to continue"
read nu

echo "[INFO] Start "
if [ $branch_type == "master" ];then
	cd /mnt/race_build/race_mq/main/master/$race_branch
	if [ $? != 0 ];then
		echo "[ERROR] Specified build/branch under ${branch_type} does not exist"
		exit 1
	fi
	scp race_xiv.tar.gz $system_name:/local/scratch
else
	cd /mnt/race_build/race_mq/side/$race_branch
	if [ $? != 0 ];then
		echo "[ERROR] Specified build/branch under ${branch_type} does not exist"
		exit 1
	fi
	side_branch_folder=`cat latest`
	cd /mnt/race_build/race_mq/side/$race_branch/$side_branch_folder
	if [ $? != 0 ];then
		echo "[ERROR] Failed to locate the required folder under branch ${race_branch} of type ${branch_type}, folder does not exist"
		exit 1
	fi
	scp race_xiv.tar.gz $system_name:/local/scratch
fi
a9k_replace_race
