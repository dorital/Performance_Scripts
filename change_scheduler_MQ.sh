#!/bin/bash
#
# This script gets as input: scheduler type. 
# This script has internal definitions of host_list
# Then it modifies the requird hosts with the requested schediuler 
#
#
# General Script Setup
is_it_vlan="no"
is_it_nvme="yes"
#
to_set_mq="no"
enable_mq="no"
#
to_set_scheduler="yes"
to_set_dm_scheduler="yes"
to_set_block_scheduler="no"
scheduler="mq-deadline" # SCSI=noop, deadline NVMe=none, mq-deadline
#
hostlist=(rmhost1 rmhost2 rmhost3)
#hostlist=(chost62 chost63 chost68 chost69)

function indexof {
i=0;
while [ "$i" -lt "${#hostlist[@]}" ] && [ "${hostlist[$i]}" != "$1" ]; do
	((i++));
done;
echo $i;
#return $i
}
#
### main ###
#if [ $# != 1 ];then
#	echo "sample: $0 noop"
#	echo "schedulers types are: noop / deadline / mq / NOmq"
#	exit 1
#fi
#scheduler=$1

function set_mq {
	if [ $is_it_nvme == "yes" ];then
		if [ $enable_mq == "yes" ];then
			echo "[INFO] Enabling MQ on host $host with NVMe"
			ssh $host cat /proc/cmdline |grep -E "dm_mod.use_blk_mq=y" > /dev/null
			if [[ $? -eq 0 ]]; then
				echo "[WARN] DM Multi-Queue is already configured on host $host"
				return 0
			else
				echo "[INFO] backup existing grub2 configurationon host $host" 
				ssh $host cp /etc/default/grub /etc/default/grub-bkp
				ssh $host cp /boot/grub2/grub.cfg /boot/grub2/grub.cfg-bkp
				ssh $host "sed -i -e 's/quiet/quiet dm_mod.use_blk_mq=y/g' /etc/default/grub"
				if [[ $? -ne 0 ]];then
					echo "[ERROR] failed to modify /etc/default/grub, exiting"
					exit 1
				fi
				ssh $host cat /etc/default/grub | grep GRUB_CMDLINE_LINUX
				ssh $host grub2-mkconfig -o /boot/grub2/grub.cfg
				ssh $host cat /boot/grub2/grub.cfg | grep linux16
				return 1
			fi
		else
			echo "[INFO] Disabling MQ on host $host with NVMe"
			ssh $host cat /proc/cmdline |grep -E "dm_mod.use_blk_mq=y" > /dev/null
			if [[ $? -ne 0 ]];then
				echo "[WARN] DM Multi-Queue is not configured on host $host"
				return 0
			else
				echo "[INFO] removing Multi-Queue support on host $host"
				ssh $host "sed -i -e 's/quiet dm_mod.use_blk_mq=y/quiet/g' /etc/default/grub"
				if [[ $? -ne 0 ]];then
					echo "[ERROR] failed to modify /etc/default/grub, exiting"
					exit 1
				fi
				ssh $host cat /etc/default/grub | grep GRUB_CMDLINE_LINUX
				ssh $host grub2-mkconfig -o /boot/grub2/grub.cfg
				ssh $host cat /boot/grub2/grub.cfg | grep linux16
				return 1
			fi
		fi
	else
		if [ $enable_mq == "yes" ];then
			echo "[INFO] Enabling MQ on host $host with SCSI"
			ssh $host cat /proc/cmdline |grep -E "scsi_mod.use_blk_mq=y*.dm_mod.use_blk_mq=y" > /dev/null
			if [[ $? -eq 0 ]]; then
				echo "[WARN] SCSI and DM Multi-Queue is already configured on host $host"
				return 0
			else
				echo "[INFO] backup existing grub2 configurationon host $host" 
				ssh $host cp /etc/default/grub /etc/default/grub-bkp
				ssh $host cp /boot/grub2/grub.cfg /boot/grub2/grub.cfg-bkp
				ssh $host "sed -i -e 's/quiet/quiet scsi_mod.use_blk_mq=y dm_mod.use_blk_mq=y/g' /etc/default/grub"
				if [[ $? -ne 0 ]];then
					echo "[ERROR] failed to modify /etc/default/grub, exiting"
					exit 1
				fi
				ssh $host cat /etc/default/grub | grep GRUB_CMDLINE_LINUX
				ssh $host grub2-mkconfig -o /boot/grub2/grub.cfg
				ssh $host cat /boot/grub2/grub.cfg | grep linux16
				return 1
			fi
		else
			echo "[INFO] Disabling MQ on host $host with SCSI"
			ssh $host cat /proc/cmdline |grep -E "scsi_mod.use_blk_mq=y*.dm_mod.use_blk_mq=y" > /dev/null
			if [[ $? -ne 0 ]];then
				echo "[WARN] SCSI and DM Multi-Queue is not configured on host $host"
				return 0
			else
				echo "[INFO] removing Multi-Queue support on host $host"
				ssh $host "sed -i -e 's/quiet scsi_mod.use_blk_mq=y dm_mod.use_blk_mq=y/quiet/g' /etc/default/grub"
				if [[ $? -ne 0 ]];then
					echo "[ERROR] failed to modify /etc/default/grub, exiting"
					exit 1
				fi
				ssh $host cat /etc/default/grub | grep GRUB_CMDLINE_LINUX
				ssh $host grub2-mkconfig -o /boot/grub2/grub.cfg
				ssh $host cat /boot/grub2/grub.cfg | grep linux16
				return 1 
			fi
		fi
	fi
}

function set_scheduler {
	if [ $scheduler == "noop" ] || [ $scheduler == "none" ] || [ $scheduler == "deadline" ] || [ $scheduler == "mq-deadline" ];then
		# check if MQ is disabled then none is changed to noop and mq-dealine is changed to deadline 				
		dm_mq=`ssh $host "cat /sys/module/dm_mod/parameters/use_blk_mq"`
		if [ $dm_mq == "N" ];then
			if [ $scheduler == "none" ];then
				dm_scheduler="noop"
			elif [ $scheduler == "mq-deadline" ];then
				dm_scheduler="deadline"
			else
				dm_scheduler=$scheduler
			fi
		else
			dm_scheduler=$scheduler
		fi
		if [ $is_it_nvme == "yes" ];then
			if [ $scheduler == "none" ] || [ $scheduler == "mq-deadline" ]; then
				echo "[INFO] Setting scheduler $scheduler on host $host with NVMe"
				ssh $host "service multipathd start"
				sleep 5
				for dm in `ssh $host "ls -d /sys/block/dm-*"`;do
					if [ $to_set_block_scheduler == "yes" ];then
						for blk_device in `ssh $host ls $dm/slaves/`;do
							device=`ssh $host cat $dm/slaves/$blk_device/device/model`
							if [ $device == "2810XIV" ];then
								ssh $host "echo $scheduler > $dm/slaves/$blk_device/queue/scheduler"
								echo "scheduler for ${dm}/slaves/${blk_device}/queue/scheduler is:"
								ssh $host cat $dm/slaves/$blk_device/queue/scheduler
							else
								echo "/sys/block/$dm/slaves/$blk_device/ not a XIV"
							fi
						done
					fi
					if [ $to_set_dm_scheduler == "yes" ];then
						# check if MQ is enabled, is yes then noop is changed to none				
	#					dm_mq=`ssh $host "cat /sys/module/dm_mod/parameters/use_blk_mq"`
	#					if [ $dm_mq == "N" ];then
	#						if [ $scheduler == "none" ];then
	#							$scheduler = "noop"
	#							ssh $host "echo $scheduler > $dm/queue/scheduler"
	#						else
	#							$scheduler = "deadline"
	#							ssh $host "echo deadline > $dm/queue/scheduler"
	#						fi
	#						ssh $host "echo $scheduler > $dm/queue/scheduler"
	#					else
	#						ssh $host "echo $scheduler > $dm/queue/scheduler"
	#					fi
						ssh $host "echo $dm_scheduler > $dm/queue/scheduler"
						echo "scheduler for ${dm}/queue/scheduler is:"
						ssh $host cat $dm/queue/scheduler
					fi
				done
			else
				echo "[ERROR] Specified scheduler does not support NVMe"
				exit 1
			fi
		else
			if [ $scheduler == "noop" ] || [ $scheduler == "deadline" ]; then
				echo "[INFO] Setting scheduler $scheduler on host $host with SCSI"
				for dm in `ssh $host "ls -d /sys/block/dm-*"`;do
					for blk_device in `ssh $host ls $dm/slaves/`;do
						device=`ssh $host cat $dm/slaves/$blk_device/device/model`
						if [ $device == "2810XIV" ];then
							ssh $host "echo $scheduler > $dm/slaves/$blk_device/queue/scheduler"
							echo "scheduler for ${dm}/slaves/${blk_device}/queue/scheduler is:"
							ssh $host cat $dm/slaves/$blk_device/queue/scheduler
						else
							echo "/sys/block/$dm/slaves/$blk_device/ not a XIV"
						fi
					done
					ssh $host "echo $dm_scheduler > $dm/queue/scheduler"
					echo "scheduler for ${dm}/queue/scheduler is:"
					ssh $host cat $dm/queue/scheduler
				done
			else
				echo "[ERROR] Specified scheduler does not support SCSI"
				exit 1
			fi
		fi
	else
		echo "[ERROR] Invalid scheduler specified"
		exit 1
	fi
	if [ `ssh $host 'cat /sys/block/dm-*/queue/scheduler|grep -w "${dm_scheduler}" -c'` == `ssh $host 'multipath -ll|grep 2810 -c'` ];then
		echo "[INFO] - all dm devices were modified successfully on host $host"
	else
		echo "[ERROR] - inconsistency between modified vs. defiend dm devices on host $host, please check"
		exit 1
	fi
	if [ `ssh $host 'cat /sys/block/dm-*/slaves/*/queue/scheduler |grep -w "${scheduler}" -c'` == `ssh $host 'multipath -ll|grep "active.*running" -c'` ];then
		echo "[INFO] - all block devices were modified successfully on host $host"
	else
		echo "[ERROR] - inconsistency between modified vs. defiend block devices on host $host, please check"
		exit 1
	fi
}

echo "Script input parms are: "$@
echo "Script internal parms are:"
echo -e "host list:\t\t"${hostlist[@]}
echo -e "to set mq:\t\t"${to_set_mq}
echo -e "to enable mq:\t\t"${enable_mq}
echo -e "to set scheduler:\t"${to_set_scheduler}
echo -e "to set DM scheduler:\t"${to_set_dm_scheduler}
echo -e "to set block scheduler:\t"${to_set_block_scheduler}
echo -e "scheduler is:\t\t"${scheduler}
echo -e "is it NVMe:\t\t"${is_it_nvme}
echo -e "press enter to continue"
read nu

for host in "${hostlist[@]}";do
	echo "[INFO] Start scheduler & MQ setup on host $host"
	if [ $to_set_scheduler == "yes" ];then
		echo "[INFO] Start scheduler setup on host $host"
		set_scheduler
	fi
	if [ $to_set_mq == "yes" ];then
		echo "[INFO] Start MQ setup on host $host"
		set_mq
		if [ $? -eq 1 ]; then
			echo "[INFO] press any kewy to reboot host $host"
			read nu
			ssh $host reboot
		else
			echo "[INFO] host $host is already configured, no need to reboot"
		fi
	fi
	echo "[INFO] End scheduler & MQ setup on host $host"
done


