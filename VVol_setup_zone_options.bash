#!/bin/bash
#
# This script gets as input: system_name, active dataset and volume number. 
# This script has internal definitions of host_list, protocol, system clean, system setup.
# Then it creates basic vdbench output
#
#
# General Script Setup
to_clean_system="no" 
to_do_fccon="no"
to_setup_system="yes"
to_create_vdbench="no"
is_it_iSCSI="no"
is_it_nvme="no"
zone_model="H" #F-Full, H-Half, S-Single
sia_user="ibmsc"
sia_user_password="P@ssw0rd"
system_name="gen4d-pod-331"
active_dataset=8000
test_name="perf_vvol"
pe_number=1
#hostlist=(tile1 tile2 tile3 tile4 tile5 tile6 tile7 tile8 tile9 til10 tile11 tile12 tile13 tile14 tile15 tile16 tile17 tile18 tile19 tile20)
hostlist=(tile1)

function system_clean {
echo "[INFO] Start - system $system_name cleanup"
echo "[INFO] Start - vol unmap, delete and pool deletion"
vol_clean_list=`ssh $system_name xcli.py vol_list pool=$pool_name -z|awk '{print$1}'`
#vol_clean_list=`ssh $system_name xcli.py -z mapping_list|awk -F " " '{print $2}'`
for vol_clean in $vol_clean_list;do
	unmap_host=`ssh $system_name xcli.py vol_mapping_list vol=$vol_clean -z | awk '{print $1}'`
	ssh $system_name xcli.py unmap_vol vol=$vol_clean host=$unmap_host -y 1> /dev/null
	ssh $system_name xcli.py cg_remove_vol -y vol=$vol_clean 1> /dev/null
	ssh $system_name xcli.py vol_delete -y vol=$vol_clean 1> /dev/null
done
echo "[INFO] End - vol unmap, delete and pool deletion"
echo "[INFO] Start - cg and pool deletion"
ssh $system_name xcli.py cg_delete cg=cg_$pool_name 1> /dev/null
ssh $system_name xcli.py pool_delete -y pool=$pool_name 1> /dev/null
echo "[INFO] End - cg and pool deletion"
#
#
echo "[INFO] Start - host cleaning"
for host in "${hostlist[@]}";do
	echo $host
    ssh $system_name xcli.py host_delete host=$host -y 1> /dev/null
done
echo "[INFO] End - host cleaning"
echo "[INFO] End - system $system_name cleanup"
#
}

function fccon {
echo "[INFO] Start - deleting all exiting zones for ${system_name}"
ssh stcon "/opt/FCCon/fcconnect.pl -op DisConnectAll -stor ${system_name}"
echo "[INFO] End - deleting all exiting zones for ${system_name}"
echo "[INFO] Start - creating new zones for ${system_name}"
# creating storage wwpn list based on zone model for stcon
stcon_storage=""
add_to_zone="yes"
for storage_wwpn in `ssh $system_name xcli.py fc_port_list -z|grep "Target.*Online"|awk '{print $4}'`;do
    if [[ "$zone_model" == "S" ]]; then
        stcon_storage="$stcon_storage -wwn $storage_wwpn"
        break
    elif [[ "$zone_model" == "H" ]]; then
        if [[ "$add_to_zone" == "yes" ]]; then
            stcon_storage="$stcon_storage -wwn $storage_wwpn"
            add_to_zone="no"
        else
            add_to_zone="yes"
        fi
    else
        stcon_storage="$stcon_storage -wwn $storage_wwpn"
    fi
done
echo $stcon_storage
for host in "${hostlist[@]}";do 
# this is true for Isolated network only	
		host_ip=`ssh -t perf-proxy ssh perf-util cat /etc/dhcp/dhcpd.conf |grep -w $host|awk -F " |;" '{print $9}'`
		ssh -t perf-proxy ssh perf-util ping -c1 $host_ip > /dev/null
		if [[ $? -ne 0 ]]; then
		   echo "[ERROR] No netwrok connectivity to host $host, ping failed. Existing"
		   exit 1
		fi
		host_fc_wwpn=`ssh perf-proxy ssh $host_ip esxcli storage san fc list |grep "Port Name"|awk '{print $3}'`
		zone=1
		for fc_wwpn in $host_fc_wwpn;do
			ssh stcon "/opt/FCCon/fcconnect.pl -op CreateZone -zone Z_${system_name}-${host}_${zone} -wwn $fc_wwpn $stcon_storage"
			((zone++))
		done
done
echo "[INFO] End - creating new zones for ${system_name}"
}

function system_setup {
echo "[INFO] Start system $system_name $interface VVol setup"
if [ "$interface" == "iscsi" ]; then
	if [ "$is_it_vlan" == "yes" ]; then
		echo "[INFO] Requested iSCSI is VLAN Tagging"
	else 
		ssh $system_name /local/scratch/$system_name"_iscsi.sh"
		target_subnet1_ip=`ssh $system_name xcli.py ipinterface_list |grep -m 1 -i 172.18.5 |awk -F " " '{print $6}'`
		target_subnet2_ip=`ssh $system_name xcli.py ipinterface_list |grep -m 1 -i 172.18.6 |awk -F " " '{print $6}'`
		# get A9K IQN
		a9k_iqn=`ssh $system_name xcli.py config_get |grep iscsi_name|awk -F " " '{print $2}'`	
	fi
	echo "$system_name iSCSI interfaces:"
	ssh $system_name xcli.py ipinterface_list | grep -i iscsi
elif [ $is_it_nvme == "yes" ]; then
	echo "[INFO] Requested FC configuration is NVMe"
	echo "[INFO] Verifying FC cards on all modules for system $system_name to support NVMe"
	for module in `ssh $system_name xcli.py module_list -z|awk '{print $1}'|awk -F":" '{print $3}'`;do
		for fc in `ssh $system_name ssh module-$module lspci -n | grep 1077|awk '{print $3}'|awk -F':' '{print $2}'`;do
			if [ $fc != "2261" ]; then
				echo "[WARM] FC on module $module on system $system_name is $fc. It does not support NVMe"
				exit 1
			fi
		done
	done
	echo "[INFO] Verifying FC cards firmware on system $system_name to support NVMe"
	for fc_fw in `ssh $system_name xcli.py fc_port_list -x |grep "active_firmware"|awk -F'"' '{print $2}'`;do
		if [ $fc_fw != "8:9:1" ]; then
				echo "[WARM] FC firmware on system $system_name is $fc_fw. It does not support NVMe"
				exit 1
		fi
	done
	echo "[INFO] FC on system $system_name supports NVMe"
	echo "[INFO] Configuring all FC cards protocol on system $system_name to be NVMe"	
	for fc_port in `ssh $system_name xcli.py fc_port_list -z|awk '{print $1}'`;do 
		ssh $system_name xcli.py fc_port_config fc_port=$fc_port fc_protocol=FC-NVMe 1>/dev/null
	done
	echo "[INFO] system $system_name FC NVMe ports:"
	ssh $system_name xcli.py fc_port_list -f component_id,protocol
fi
echo "[INFO] Start - Domain creation"
domain_size=`echo "$active_dataset*2"|bc`
domain_name=${test_name}_domain
ssh $system_name xcli.py domain_create domain=$domain_name max_pools=20 max_volumes=20000 size=$domain_size max_cgs=20 -y 1>/dev/null
ssh $system_name xcli.py domain_manage domain=$domain_name managed=yes -y 1>/dev/null
echo "[INFO] End - Domain creation"
#
echo "[INFO] Start - User Storage Integration Admin creation"
ssh $system_name xcli.py user_define user=$sia_user category=storageintegrationadmin password=$sia_user_password password_verify=$sia_user_password domain=$domain_name -y 1>/dev/null
echo "[INFO] End - User Storage Integration Admin creation"
#
for host in "${hostlist[@]}";do
	echo "[INFO] Start - host definition $host using $interface"
	ssh $system_name xcli.py host_define host=$host domain=$domain_name 1>/dev/null
	echo "ALU is created by SC"
#	for pe in $(seq 1 $pe_number);do
#		ssh $system_name xcli.py alu_create alu=${test_name}_${host}_alu${pe} host=$host lun=70${pe} 1>/dev/null
#	done
	if [ "$interface" == "iscsi" ]; then
		host_iqn=`ssh $host cat /etc/iscsi/initiatorname.iscsi|cut -d "=" -f2`
		# Adding hosts iqn on A9K system
		ssh $system_name xcli.py host_add_port host=$host iscsi_name=$host_iqn > /dev/null
		# command to verify connectivity 
		ssh $host ping -c1 $target_subnet1_ip > /dev/null
		if [[ $? -ne 0 ]]; then
		   echo "no iscsi connectivity on host $host subnet $target_subnet1_ip"
		   exit
		fi
		ssh $host ping -c1 $target_subnet2_ip > /dev/null
		if [[ $? -ne 0 ]]; then
		   echo "no iscsi connectivity on host $host subnet $target_subnet2_ip"
		   exit
		fi
		echo "iscsi connectivity is OK on host $host for both subnets"
		#
		# command to verify mtu=9000, jambo frames
		ssh $host traceroute -m 1 -4 --mtu $target_subnet1_ip|grep -E "$target_subnet1_ip.*9000" > /dev/null
		if [[ $? -ne 0 ]]; then
		   echo "MTU is not 9000 on host $host subnet $target_subnet1_ip"
		   exit 
		fi
		ssh $host traceroute -m 1 -4 --mtu $target_subnet2_ip|grep -E "$target_subnet2_ip.*9000" > /dev/null
		if [[ $? -ne 0 ]]; then
		   echo "MTU is not 9000 on host $host subnet $target_subnet2_ip"
		   exit 
		fi
		echo "MTU 9000 is OK on host $host for both subnets"

		#
		# checking if iscsi service is running
		ssh $host systemctl status iscsid.service |grep running > /dev/null
		if [[ $? -ne 0 ]]; then
		   echo "iscsid service is down on host $host"
		   exit
		fi
		echo "iscsid service is OK on host $host"
		# Cleaning iSCSI
		echo "Start - Cleaning host $host iSCSI and luns"
		for i in `ssh $host iscsiadm -m node|sed 's/ /,/g'`;do
		   portal=`echo $i |cut -f1 -d","`
		   target_iqn=`echo $i|cut -f3 -d","`
		   ssh $host iscsiadm -m node -u -T $target_iqn -p $portal
		   ssh $host iscsiadm -m node -o delete -T $target_iqn -p $portal
		done
		for i in `ssh $host iscsiadm -m discovery`;do
		   discovery=`echo $i |cut -f1 -d" "`
		   ssh $host iscsiadm -m discoverydb -t sendtargets -o delete -p $discovery
		done
		echo "End - Cleaning host $host iSCSI and luns"
		#
		#start_count=`echo $(($start_count+$host_mapping))` 
		#end_count=`echo $(($end_count+$host_mapping))` 
		echo "Start -  Connecting host $host to iSCSI and luns"
		# discover the A9K target ips
		ssh $host iscsiadm -m discovery -t st -p $target_subnet1_ip 
		#OR iscsiadm --mode discovery -t sendtargets --portal 172.18.5.36
		# Login to the A9K discovered targets
		ssh $host iscsiadm -m node -l -n $a9k_iqn
		#
		ssh $host rescan-scsi-bus.sh -r -f > /dev/null
		ssh $host multipath -F > /dev/null
		ssh $host multipath > /dev/null
		echo "End -  Connecting host $host to iSCSI and luns"
	else
# this is true for Isolated network only	
		host_ip=`ssh -t perf-proxy ssh perf-util cat /etc/dhcp/dhcpd.conf |grep -w $host|awk -F " |;" '{print $9}'`
		ssh -t perf-proxy ssh perf-util ping -c1 $host_ip > /dev/null
		if [[ $? -ne 0 ]]; then
		   echo "[ERROR] No netwrok connectivity to host $host, ping failed. Existing"
		   exit 1
		fi
		host_fc_wwpn=`ssh perf-proxy ssh $host_ip esxcli storage san fc list |grep "Port Name"|awk '{print $3}'`
		for fc_wwpn in $host_fc_wwpn;do
		# Adding hosts wwpn on A9K system
			ssh $system_name xcli.py host_add_port host=$host fcaddress=$fc_wwpn
		done
		if [ $is_it_nvme == "yes" ];then
			echo "[INFO] Requested FC protocol is NVMe, verifying and configuring host $host to support NVMe"
			echo "[INFO] Verifying host $host FC firmware to support NVMe"
			for host_fc_fw in `ssh $host qaucli -i |grep "Running Firmware Version"|awk '{print $5}'`;do
				if [ $host_fc_fw != "8.09.01" ]; then
					echo "[WARN] FC firmware $host_fc_fw on host $host does not support NVMe"
					exit 1
				fi
			done
			echo "[INFO] Verifying host $host FC driver to support NVMe"
			for host_fc_driver in `ssh $host qaucli -i |grep "Driver"|awk '{print $4}'|awk '{print $1}'`;do
				if [ $host_fc_driver != "10.01.00.23.15.0-k1" ]; then
					echo "[WARN] FC driver $host_fc_driver on host $host does not support NVMe"
					exit 1
				fi
			done
			echo "[INFO] stopping multipath on host $host"
			ssh $host service multipathd stop
		else
			echo "[INFO] Start - rescan on host $host"
			ssh -t perf-proxy ssh $host_ip esxcli storage core adapter rescan --all
			echo "[INFO] End - rescan on host $host"
		fi
	fi
	echo "[INFO] End - host definition $host using $interface"
echo "[INFO] End system $system_name $interface setup"
done
}

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

echo "Script input parms are: "$@
echo "Script internal parms are:"
echo -e "to_clean_system:\t"$to_clean_system
echo -e "to_do_fccon:\t\t"$to_do_fccon
echo -e "Zone model:\t\t"$zone_model "\t(F-Full, H-Half, S-Single)"
echo -e "to_setup_system:\t"$to_setup_system
echo -e "to_create_vdbench:\t"$to_create_vdbench
echo -e "is_it_iSCSI:\t\t"$is_it_iSCSI
echo -e "is_it_nvme:\t\t"$is_it_nvme
echo -e "host list:\t\t"${hostlist[@]}
echo -e "system name:\t\t"$system_name
echo -e "active dataset size:\t"$active_dataset
echo -e "test name:\t\t"$test_name
echo -e "Number of PE:\t\t"$pe_number
echo -e "press enter to continue"
read nu

#host_number=`echo ${#hostlist[@]}`

if [ $is_it_iSCSI == "yes" ];then
	echo "[INFO] Requested protocol is iSCSI"
	interface="iscsi"
else
	echo "[INFO] Requested protocol is FC"
	interface="fc"
fi
#
if [ $to_clean_system == "yes" ];then
	echo "[INFO] Running system cleaning"
	system_clean
else
	echo "[INFO] Not running system cleaning"
fi
#
if [ $to_do_fccon == "yes" ];then
	echo "[INFO] Running FCCon setup"
	fccon
else
	echo "[INFO] Not running FCCon setup"
fi
#
if [ $to_setup_system == "yes" ];then
	echo "[INFO] Running system setup"
	system_setup
else
	echo "[INFO] Not running system setup"
fi
#exit
#
if [ $to_create_vdbench == "yes" ];then
	echo "[INFO] Running vdbench config creation"
	sd=0
	vdbench_vol_size=`echo "$vol_size/1.1"|bc`
	vdbench_sd_output="${system_name}_${interface}_${active_dataset}GB_vdbench_config"
	rm -f /root/vdbench/$vdbench_sd_output
	echo "compratio=2.86" > /root/vdbench/$vdbench_sd_output
	echo "#dedupratio=2,dedupunit=8k,dedupsets=5%" >> /root/vdbench/$vdbench_sd_output
	echo "debug=25" >> /root/vdbench/$vdbench_sd_output
	echo "hd=default,vdbench=/root/vdbench//bin,user=root,shell=ssh" >> /root/vdbench/$vdbench_sd_output
	for host in "${hostlist[@]}";do 
		hd=$( indexof $host )
		echo "hd=hd$hd,system=$host" >> /root/vdbench/$vdbench_sd_output
	done
	#
	system_serial=`ssh $system_name xcli.py config_get |grep system_id |awk '{print $2}'`
	system_serial_hex=`echo "obase=16; $system_serial"|bc`
	if [ $is_it_nvme == "yes" ];then
		for host in "${hostlist[@]}";do 
			echo "$host"
			ssh $host "service multipathd stop" > /dev/null
			#ssh $host modprobe -r qla2xxx
			#sleep 5
			#ssh $host modprobe qla2xxx
			#sleep 15
			hd=$( indexof $host )
			for nvme_dev in `ssh $host nvme list |grep -i $system_serial | awk '{print $1}'`;do  
				echo "sd=sd$sd,host=hd$hd,lun=$nvme_dev,openflags=(o_direct,o_sync,fsync),size=$vdbench_vol_size""g,threads=10,hitarea=170m" >> /root/vdbench/$vdbench_sd_output
				((sd++))
			done
		done
	else
		for host in "${hostlist[@]}";do 
			echo "$host"
			ssh $host "rescan-scsi-bus.sh" > /dev/null
			ssh $host "multipath -F" > /dev/null
			ssh $host "multipath" > /dev/null
			hd=$( indexof $host )
		#	indexof "$host"
		#	echo $?
		#	hd=$?
		#	echo $hd
		# use list of mapping volumes based on name,pool_name and wwn - xcli.py vol_list -f name,pool_name,wwn
		# for each volume checkon the host the attached mpath using the wwn
			for dm in `ssh $host multipath -ll |grep -i $system_serial_hex |cut -f2 -d"-"|cut -f1 -d" "|sort -n`;do  
				echo "sd=sd$sd,host=hd$hd,lun=/dev/dm-$dm,openflags=(o_direct,o_sync,fsync),size=$vdbench_vol_size""g,threads=10,hitarea=170m" >> /root/vdbench/$vdbench_sd_output
				((sd++))
			done
		done
	fi
	echo "rd=default,xfersize=8k,iorate=curve,curve=(10,25,50,65,70,80,90,100),elapsed=10m,interval=10,openflags=o_direct,hitarea=500m,pause=30m" >> /root/vdbench/$vdbench_sd_output
	echo "rd=prealloc,sd=*,elapsed=100h,interval=10,rdpct=0,openflags=o_direct,iorate=max,xfersize=256K,seekpct=0,maxdata=1,threads=1,pause=5m" >> /root/vdbench/$vdbench_sd_output
	echo "rd=warmup,sd=*,elapsed=20m,interval=10,openflags=o_direct,iorate=max,xfersize=1m,rhpct=100,whpct=100,pause=1m" >> /root/vdbench/$vdbench_sd_output
	echo "rd=Read_Hit_8K,sd=*,rhpct=100,whpct=100,curve=(10,25,50,65,70,80,83,86,90,92,94,96,98,100),pause=1m" >> /root/vdbench/$vdbench_sd_output
	echo "rd=Read_Miss_8K,sd=*,rdpct=100,curve=(10,25,50,65,70,80,83,86,90,92,94,96,98,100),pause=1m" >> /root/vdbench/$vdbench_sd_output
	echo "rd=70_30_8K,sd=*,rdpct=70" >> /root/vdbench/$vdbench_sd_output
	echo "rd=70_30_80%_Hit_8K,sd=*,rdpct=70,rhpct=80,whpct=72" >> /root/vdbench/$vdbench_sd_output
	echo "rd=Write_Hit_8K,sd=*,rdpct=0,rhpct=100,whpct=100,pause=5m" >> /root/vdbench/$vdbench_sd_output
	echo "rd=30min_pause_4_8k,sd=*,rdpct=100,elapsed=1m,interval=30,iorate=1,pause=30m" >> /root/vdbench/$vdbench_sd_output
	echo "rd=Write_Miss_8K,sd=*,rdpct=0" >> /root/vdbench/$vdbench_sd_output
	echo "[INFO} vdbench config file was created: /root/vdbench/$vdbench_sd_output"
else
	echo "[INFO] Not running vdbench config creation"
fi

exit
