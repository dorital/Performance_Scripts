#this script enables you to setup a Linux host with its iso image, blast and HAK
#!/bin/sh
#
# Function for doing remote installation for  latest code
#
function Remote_install {
	echo "select major release"
	OPTIONS="11 12 SA" 
	select opt in $OPTIONS; do
		case $opt in 
	        "11" )
			major_release=$opt
			break
			;;
	        "12" )
			major_release=$opt
			break
			;;
	        "SA" )
			OPTIONS="SA1 SA2 SA3" 
			select opt in $OPTIONS; do
				case $opt in 
					"SA1" )
					major_release="11.5.0.b/purple"
					break
					;;
					"SA2" )
					major_release="11.5.1.c/purple"
					break
					;;
					"SA3" )
					major_release="11.5.3/purple"
					break
					;;
				esac
			done
			break
			;;
			"x" )
			exit
			;;
			* )
			echo "bad option"
			;;
		esac
	done
echo $major_release |grep purple > /dev/null
if [[ $? = 0 ]]; then
	echo "enter SA machine to be installed"
	read SA_machine
	echo ""/a/system_builds/leia/remoteinstall /qa/system_builds/$major_release/xiv_sds_deployment_kit-latest.bash -s $SA_machine""
else
	OPTIONS=`ls -d /qa/system_builds/$major_release*`
	select opt in $OPTIONS; do
		release=$opt
		echo "enter XIV machine to be installed"
		read XIV_machine
		echo "Enter any required flags for install"
		echo "Available flags:"
		echo "Upgrade machine firmwares: --upgrade-firmware"
		echo "Skip TMS firmware verification: --skip-flash-fw-check"
		echo "Ignore machine location (for Tel-Ad): --skip-location-check"
		echo "Reformat machine: --reformat-system"
		read flags
		/a/system_build/leia/remoteinstall $XIV_machine $release/ixss-symlink-current-folder-internal-latest.tar.gz $flags
		break
	done
fi
echo "verify successful installation"
ssh $XIV_machine xcli.py state_list 
ssh $XIV_machine xcli.py component_list filter=notok
ssh $XIV_machine event_proc.py -g fail
}
#
# Function for doing remote installation for selected code
#
function Remote_Install_Specific {
	echo "select major release"
	OPTIONS="11 12 SA" 
	select opt in $OPTIONS; do
		case $opt in 
	        "11" )
			major_release=$opt
			break
			;;
	        "12" )
			major_release=$opt
			break
			;;
	        "SA" )
			OPTIONS="SA1 SA2 SA3" 
			select opt in $OPTIONS; do
				case $opt in 
					"SA1" )
					major_release="11.5.0.b/purple"
					break
					;;
					"SA2" )
					major_release="11.5.1.c/purple"
					break
					;;
					"SA3" )
					major_release="11.5.3/purple"
					break
					;;
				esac
			done
			break
			;;
			"x" )
			exit
			;;
			* )
			echo "bad option"
			;;
		esac
	done
echo $major_release |grep purple > /dev/null
if [[ $? = 0 ]]; then
	echo "enter SA machine to be installed"
	read SA_machine
	echo ""/a/system_builds/leia/remoteinstall /qa/system_builds/$major_release/xiv_sds_deployment_kit-latest.bash -s $SA_machine""
else
	OPTIONS=`ls -d /qa/system_builds/$major_release*`
	select opt in $OPTIONS; do
		release=$opt
		OPTIONS=`ls $release/`
		select opt in $OPTIONS; do
			specific_code=$opt
			echo "enter XIV machine to be installed"
			read XIV_machine
			`/a/system_build/leia/remoteinstall $XIV_machine $release/$specific_code`
			break
		done
		break 
	done
fi
echo "verify successful installation"
ssh $XIV_machine xcli.py state_list 
ssh $XIV_machine xcli.py component_list filtre=notok
ssh $XIV_machine xcli.py event_proc.py -g fail
}
#
# Function for doing remote code upgrade 
#
function Remote_Upgrade {
	echo "select major release"
	OPTIONS="11 12 SA" 
	select opt in $OPTIONS; do
		case $opt in 
	        "11" )
			major_release=$opt
			break
			;;
	        "12" )
			major_release=$opt
			break
			;;
	        "SA" )
			OPTIONS="SA1 SA2 SA3" 
			select opt in $OPTIONS; do
				case $opt in 
					"SA1" )
					major_release="11.5.0.b/purple"
					break
					;;
					"SA2" )
					major_release="11.5.1.c/purple"
					break
					;;
					"SA3" )
					major_release="11.5.3/purple"
					break
					;;
				esac
			done
			break
			;;
			"x" )
			exit
			;;
			* )
			echo "bad option"
			;;
		esac
	done
echo $major_release |grep purple > /dev/null
if [[ $? = 0 ]]; then
	echo "enter SA machine to be installed"
	read SA_machine
	echo ""/a/system_builds/leia/remoteinstall /qa/system_builds/$major_release/xiv_sds_deployment_kit-latest.bash -s $SA_machine""
else
	OPTIONS=`ls -d /qa/system_builds/$major_release*`
	select opt in $OPTIONS; do
		release=$opt
		OPTIONS=`ls $release/`
		select opt in $OPTIONS; do
			specific_code=$opt
			echo "enter XIV machine to be upgraded"
			read XIV_machine
			echo "*** Deleting old existing packages ***"
			ssh root@$XIV_machine  rm -fr /local/scratch/ixss*
			echo "*** Coping selected package - $specific_code ***"
			scp $release/$specific_code root@$XIV_machine:/local/scratch/
			scp /mnt/Interop/Scripts/XIV_hot_upgrade_v1.sh root@$XIV_machine:/local/scratch/
			ssh root@$XIV_machine  tar -xvf /local/scratch/$specific_code -C /local/scratch/
			ssh root@$XIV_machine  /local/scratch/XIV_hot_upgrade_v1.sh
			break
		done
		break 
	done
fi
echo "verify successful installation"
ssh $XIV_machine xcli.py state_list 
ssh $XIV_machine xcli.py component_list filtre=notok
ssh $XIV_machine xcli.py event_proc.py -g fail
}
#
# Function for doing git code build and installation  
#
function Build_and_Install_Code {
	cd /local/iop/git/p11.0/leia/
	echo "*** Listing existing branches ***"
	git branch
	OPTIONS="Install_from_new_branch Install_from_existing_branch" 
	select opt in $OPTIONS; do
		case $opt in 
		"Install_from_new_branch" )
			echo "*** Please enter desired remote branch or prefix ***"
			read prefix_branch
#			OPTIONS=`git branch -a |cut -c 3- | grep $prefix_branch`
#			select opt in $OPTIONS; do
#				remote_branch=$opt
				remote_branch=`git branch -a |cut -c 3- | grep $prefix_branch`
				echo "*** enter local branch name ***"
				read branch
				git checkout -b $branch $remote_branch 
				break
#			done
		;;
		"Install_from_existing_branch" )
			OPTIONS=`git branch | cut -c 3-`
			select opt in $OPTIONS; do
				branch=$opt
				git checkout $branch	
				break
			done
		;;
		"x" )
			exit
			;;
		* )
			echo "bad option"
		;;
		esac
		break
	done
	git pull
	git branch
	echo "Enter XIV machine to be upgraded"
	read XIV_machine
	`./xtool.py build install -s $XIV_machine`
	echo "verify successful installation"
	ssh $XIV_machine xcli.py state_list 
	ssh $XIV_machine xcli.py component_list filtre=notok
	ssh $XIV_machine xcli.py event_proc.py -g fail
}
#
# Function for doing git code build and installation  
#
function Build_and_Install_Specific_Code {
	cd /local/iop/git/p11.0/leia/
	echo "*** Listing existing branches ***"
	git branch
	git pull
	OPTIONS="Install_from_new_branch Install_from_existing_branch" 
	select opt in $OPTIONS; do
		case $opt in 
		"Install_from_new_branch" )
			echo "*** Please enter desired remote branch or prefix ***"
			read prefix_branch
			OPTIONS=`git branch -a |cut -c 3- | grep $prefix_branch`
			select opt in $OPTIONS; do
				remote_branch=$opt
				echo "*** enter local branch name ***"
				read branch
				git checkout -b $branch $remote_branch 
				break
			done
		;;
		"Install_from_existing_branch" )
			OPTIONS=`git branch | cut -c 3-`
			select opt in $OPTIONS; do
				branch=$opt
				git checkout $branch	
				break
			done
		;;
		"x" )
			exit
			;;
		* )
			echo "bad option"
		;;
		esac
		break
	done
#	git pull
#	echo "Enter desired commit hash"
#	read commit_hash
#	git reset --hard $commit_hash
	echo "enter XIV machine to be upgraded"
	read XIV_machine
	`./xtool.py build install -s $XIV_machine`
	echo "verify successful installation"
	ssh $XIV_machine xcli.py state_list 
	ssh $XIV_machine xcli.py component_list filtre=notok
	ssh $XIV_machine xcli.py event_proc.py -g fail
}
#
# function to setup HA configuration between two A9K systems - from 12.1.0
#
function Build_HA_configuration {
	echo "Before setting up HA please ensure:"
	echo "* Zoning is defind fro both ways between the relevant systems"
	echo "* Each system has at least one FC defined as Initiator"
	echo "* All FC physical connectivity is working"
	echo "Ready to continure?"
	read answer
	echo "Enter Master system"
	read master_sys
	echo "Enter Slave system"
	read slave_sys
	echo "Enter Quorum name"
	read quorum_name
	echo "Enter Quorum IP address"
	read quorum_ip
	echo "Enter Quorum root password"
	read rootpwd
#
#
# Configuring systems certifications
#
	for i in $master_sys $slave_sys; do
		serial=`ssh $i xcli.py config_get |grep "machine_serial_number "|awk -F " " '{print $2}'`
		password=`ssh $i cat /local/scratch/$serial/$serial.key`
		certificate="(base64 /local/scratch/$serial/$serial.mfg)"
		ssh $i xcli.py pki_set_pkcs12 name=XIV is_default=yes services=all password=$password certificate='"$'$certificate'"' -Ud > /dev/null
	done
#
# Defining Quorum	
#
#	certificate_ha=`sshpass -p $rootpwd ssh root@$quorum_ip cat /opt/ibm/ibm_quorum_witness/settings/ssl_cert/qw.crt`
	sshpass -p $rootpwd scp root@$quorum_ip:/opt/ibm/ibm_quorum_witness/settings/ssl_cert/qw.crt ~/.
	for i in $master_sys $slave_sys; do
#		sshpass -p $rootpwd scp root@$quorum_ip:/opt/ibm/ibm_quorum_witness/settings/ssl_cert/qw.crt $i:/local/scratch/
		scp ~/qw.crt $i:/local/scratch/
#		ssh $i cat /local/scratch/qw.crt
		ssh $i xcli.py quorum_witness_define name=$quorum_name address=$quorum_ip port=8460 certificate='"`cat /local/scratch/qw.crt`"'
		ssh $i xcli.py quorum_witness_activate name=$quorum_name > /dev/null
	done		
#
# Configuring Master system
#
# Defining Slave target 
	ssh $master_sys xcli.py target_define protocol=FC xiv_features=yes target=$slave_sys -y > /dev/null
# Adding slave FC ports wwpn, should be issued for ALL FC WWN including the Initiator
	for i in `ssh $slave_sys xcli.py fc_port_list |grep -i online|awk -F " " '{print $4}'`; do
		ssh $master_sys xcli.py target_port_add target=$slave_sys fcaddress=$i > /dev/null							
	done
# Getting Master FC Initiator port name
	master_fc_init=`ssh $master_sys xcli.py fc_port_list |grep -i online|grep -i Initiator|awk -F " " '{print $1}'`
# Defining slave FC target ports wwpn, should be issued for ONLY traget FC WWN (exclude initiate FC wwpn).
	for i in `ssh $slave_sys xcli.py fc_port_list |grep -i online|grep -i target|awk -F " " '{print $4}'`; do
		ssh $master_sys xcli.py target_connectivity_define target=$slave_sys local_port=$master_fc_init fcaddress=$i > /dev/null
		ssh $master_sys xcli.py target_connectivity_activate target=$slave_sys local_port=$master_fc_init fcaddress=$i > /dev/null
	done
	ssh $master_sys xcli.py target_mirroring_allow target=$slave_sys > /dev/null
	ssh $master_sys xcli.py target_add_quorum_witness target=$slave_sys quorum_witness=$quorum_name > /dev/null
#
# Configuring Slave system
#
# Defining Master target 
	ssh $slave_sys xcli.py target_define protocol=FC xiv_features=yes target=$master_sys > /dev/null
# Adding master FC ports wwpn, should be issued for ALL FC WWN including the Initiator
	for i in `ssh $master_sys xcli.py fc_port_list |grep -i online|awk -F " " '{print $4}'`; do
		ssh $slave_sys xcli.py target_port_add target=$master_sys fcaddress=$i > /dev/null							
	done
# Getting Slave FC Initiator port name
	slave_fc_init=`ssh $slave_sys xcli.py fc_port_list |grep -i online|grep -i Initiator|awk -F " " '{print $1}'`
# Defining master FC target ports wwpn, should be issued for ONLY traget FC WWN (exclude initiate FC wwpn).
	for i in `ssh $master_sys xcli.py fc_port_list |grep -i online|grep -i target|awk -F " " '{print $4}'`; do
		ssh $slave_sys xcli.py target_connectivity_define target=$master_sys local_port=$slave_fc_init fcaddress=$i > /dev/null
		ssh $slave_sys xcli.py target_connectivity_activate target=$master_sys local_port=$slave_fc_init fcaddress=$i > /dev/null
	done
	ssh $slave_sys xcli.py target_mirroring_allow target=$master_sys > /dev/null
	ssh $slave_sys xcli.py target_add_quorum_witness  target=$master_sys quorum_witness=$quorum_name > /dev/null
# Verifying quorum was setup correctly 
	for i in $master_sys $slave_sys; do
	echo '***' $i '***'
	ssh $i xcli.py target_list 
	ssh $i xcli.py quorum_witness_list
	done		
}
function Build_Mirror_configuration {
	echo "Before setting up HA please ensure:"
	echo "* Zoning is defind fro both ways between the relevant systems"
	echo "* Each system has at least one FC defined as Initiator"
	echo "* All FC physical connectivity is working"
	echo "Ready to continure?"
	read answer
	echo "Enter Master system"
	read master_sys
	echo "Enter Slave system"
	read slave_sys
#
#
# Configuring systems certifications
#
#	for i in $master_sys $slave_sys; do
#		serial=`ssh $i xcli.py config_get |grep "machine_serial_number "|awk -F " " '{print $2}'`
#		password=`ssh $i cat /local/scratch/$serial/key`
#		certificate="(base64 /local/scratch/$serial/2810-$serial.mfg)"
#		ssh $i xcli.py pki_set_pkcs12 name=XIV is_default=yes services=all password=$password certificate='"$'$certificate'"' -Ud > /dev/null
#	done
#
# Configuring Master system
#
# Defining Slave target 
	ssh $master_sys xcli.py target_define protocol=FC xiv_features=yes target=$slave_sys -y > /dev/null
# Adding slave FC ports wwpn, should be issued for ALL FC WWN including the Initiator
	for i in `ssh $slave_sys xcli.py fc_port_list |grep -i online|awk -F " " '{print $4}'`; do
		ssh $master_sys xcli.py target_port_add target=$slave_sys fcaddress=$i > /dev/null							
	done
# Getting Master FC Initiator port name
	master_fc_init=`ssh $master_sys xcli.py fc_port_list |grep -i online|grep -i Initiator|awk -F " " '{print $1}'`
# Defining slave FC target ports wwpn, should be issued for ONLY traget FC WWN (exclude initiate FC wwpn).
	for i in `ssh $slave_sys xcli.py fc_port_list |grep -i online|grep -i target|awk -F " " '{print $4}'`; do
		ssh $master_sys xcli.py target_connectivity_define target=$slave_sys local_port=$master_fc_init fcaddress=$i > /dev/null
		ssh $master_sys xcli.py target_connectivity_activate target=$slave_sys local_port=$master_fc_init fcaddress=$i > /dev/null
	done
	ssh $master_sys xcli.py target_mirroring_allow target=$slave_sys > /dev/null
#
# Configuring Slave system
#
# Defining Master target 
	ssh $slave_sys xcli.py target_define protocol=FC xiv_features=yes target=$master_sys -y > /dev/null
# Adding master FC ports wwpn, should be issued for ALL FC WWN including the Initiator
	for i in `ssh $master_sys xcli.py fc_port_list |grep -i online|awk -F " " '{print $4}'`; do
		ssh $slave_sys xcli.py target_port_add target=$master_sys fcaddress=$i > /dev/null							
	done
# Getting Slave FC Initiator port name
	slave_fc_init=`ssh $slave_sys xcli.py fc_port_list |grep -i online|grep -i Initiator|awk -F " " '{print $1}'`
# Defining master FC target ports wwpn, should be issued for ONLY traget FC WWN (exclude initiate FC wwpn).
	for i in `ssh $master_sys xcli.py fc_port_list |grep -i online|grep -i target|awk -F " " '{print $4}'`; do
		ssh $slave_sys xcli.py target_connectivity_define target=$master_sys local_port=$slave_fc_init fcaddress=$i > /dev/null
		ssh $slave_sys xcli.py target_connectivity_activate target=$master_sys local_port=$slave_fc_init fcaddress=$i > /dev/null
	done
	ssh $slave_sys xcli.py target_mirroring_allow target=$master_sys > /dev/null
}
#Set_User_Pass 
function Set_User_Pass {
if [[ $server_ip == "" || $rootpwd == "" ]]
	then
	echo "enter target server ip"
	read server_ip
	echo "enter root password"
	read rootpwd
fi
return
}
#Install OS ISO on the host and mount it
function Install_ISO {
	if [[ $server_ip == "" || $rootpwd == "" ]]
	then
	echo "Please set default server ip and root password" 
	return
	fi
	OPTIONS=`ls /mnt/OS/linux`
	select opt in $OPTIONS; do
		echo $opt
		case $opt in 
	                	"suse" )
			final_folder="/mnt/OS/linux/$opt"
			echo $final_folder |grep -i iso > /dev/null
			while [[ $? != 0 ]]
				do
				OPTIONS="`ls $final_folder`"
				select opt in $OPTIONS; do
					final_folder=$final_folder"/"$opt
					break
				done
				echo $final_folder |grep -i iso > /dev/null
			done
			;;
			"redhat" )
			final_folder="/mnt/OS/linux/$opt"
			echo $final_folder |grep -i iso > /dev/null
			while [[ $? != 0 ]]
				do
				OPTIONS="`ls $final_folder`"
				select opt in $OPTIONS; do
					final_folder=$final_folder"/"$opt
					break
				done
				echo $final_folder |grep -i iso > /dev/null
			done
			;;
			"centos" )
			final_folder="/mnt/OS/linux/$opt"
			echo $final_folder |grep -i iso > /dev/null
			while [[ $? != 0 ]]
				do
				OPTIONS="`ls $final_folder`"
				select opt in $OPTIONS; do
					final_folder=$final_folder"/"$opt
					break
				done
				echo $final_folder |grep -i iso > /dev/null
			done
			;;
			"oracle" )
			final_folder="/mnt/OS/linux/$opt"
			echo $final_folder |grep -i iso > /dev/null
			while [[ $? != 0 ]]
				do
				OPTIONS="`ls $final_folder`"
				select opt in $OPTIONS; do
					final_folder=$final_folder"/"$opt
					break
				done
				echo $final_folder |grep -i iso > /dev/null
			done
			;;
			"x" )
			exit
			;;
			* )
			echo "bad option"
		esac
		break
	done
echo $final_folder
echo $opt
sshpass -p $rootpwd ssh root@$server_ip mkdir -p /install
if [[ $? == 0 ]]
	then
	echo "remote mkdir /install was ok"
else
	echo "remote mkdir /install failed"
	exit
fi
sshpass -p $rootpwd ssh root@$server_ip mkdir -p /media/dvd
if [[ $? == 0 ]]
	then
	echo "remote mkdir /media/dvd was ok"
else
	echo "remote mkdir /media/dvd failed"
	exit
fi
sshpass -p $rootpwd scp $final_folder root@$server_ip:/install
if [[ $? == 0 ]]
	then
	echo "iso scp was ok"
else
	echo "iso scp failed"
	exit
fi
sshpass -p $rootpwd ssh root@$server_ip mount -o loop /install/$opt /media/dvd/
if [[ $? == 0 ]]
	then
	echo "remote iso mount was ok"
else
	echo "remote iso mount failed"
	exit
fi
#exit
}

#Install Blast on the host
function Install_Blast {
	OPTIONS=`ls /mnt/Interop/Blast/`
	select opt in $OPTIONS; do
		final_folder="/mnt/Interop/Blast/$opt"
		echo $final_folder |grep blast > /dev/null
		while [[ $? != 0 ]]
			do
			OPTIONS="`ls $final_folder`"
			select opt in $OPTIONS; do
				final_folder=$final_folder"/"$opt
				break
			done
			echo $final_folder |grep blast > /dev/null
		done
		break
	done
echo $final_folder
echo $opt
sshpass -p $rootpwd ssh root@$server_ip mkdir -p /blast
if [[ $? == 0 ]]
	then
	echo "remote mkdir /blast was ok"
else
	echo "remote mkdir /blast failed"
	exit
fi
sshpass -p $rootpwd scp $final_folder root@$server_ip:/blast
if [[ $? == 0 ]]
	then
	echo "blast scp was ok"
else
	echo "blast scp failed"
	exit
fi
}

#Install HAK 
function Install_HAK {
	OPTIONS=`ls /mnt/Interop/HAK/`
	select opt in $OPTIONS; do
		final_folder="/mnt/Interop/HAK/$opt"
		echo $final_folder |grep "Host_Attachment_Kit" > /dev/null
		while [[ $? != 0 ]]
			do
			OPTIONS="`ls $final_folder`"
			select opt in $OPTIONS; do
				final_folder=$final_folder"/"$opt
				break
			done
			echo $final_folder |grep "Host_Attachment_Kit" > /dev/null
		done
		break
	done
echo $final_folder
echo $opt
sshpass -p $rootpwd ssh root@$server_ip mkdir -p /hak
if [[ $? == 0 ]]
	then
	echo "remote mkdir /hak was ok"
else
	echo "remote mkdir /hak failed"
	exit
fi
sshpass -p $rootpwd scp $final_folder root@$server_ip:/hak
if [[ $? == 0 ]]
	then
	echo "hak scp was ok"
else
	echo "hak scp failed"
	exit
fi
}

function Host_Setup {
# display the different options to the user to select from
server_ip=""
rootpwd=""
OPTIONS="Set_User_Pass Mount_wnasfs Install_ISO Install_Blast Install_HAK Do_All Return"
select opt in $OPTIONS; do
	case $opt in 
		"Set_User_Pass" )
		Set_User_Pass
		;;
		"Mount_wnasfs" )
		Mount_wnasfs
#		exit
		;;
		"Install_ISO" )
		Set_User_Pass 
		Install_ISO
#		exit
		;;
		"Install_Blast" )
		Set_User_Pass 
		Install_Blast
#		exit
		;;
		"Install_HAK" )
		Set_User_Pass 
		Install_HAK
#		exit
		;;
		"Do_All" )
		Set_User_Pass 
		Install_ISO
		Install_Blast
		Install_HAK
#		exit
		;;
		"Return" )
		return
		;;
		* )
		echo "Invalid option"
	esac
done
exit
}
function XIV_Host_Setup {
echo "enter XIV sysytem ip or name"
read xiv_system
echo "enter OS_name name"
read OSname
echo "enter Host name"
read Hostname
echo "enter number of lun"
read Lun_number
echo "enter fc or iscsi"
read interface_type
ssh $xiv_system xcli.py host_define host=$Hostname.$OSname > /dev/null
if [[ $interface_type == "fc" ]]
	then
		echo "Enter number of fc adapaters"
		read fc_number
		for i in $(seq 1 $fc_number)
		do
			echo "Enter fc adapater" $i "wwpn"
			read fc_wwpn
			ssh $xiv_system xcli.py host_add_port host=$Hostname.$OSname fcaddress=$fc_wwpn > /dev/null
		done
else
	echo "enter iSCSI IQN"
	read iscsi_iqn
	ssh $xiv_system xcli.py host_add_port host=$Hostname.$OSname iscsi_name=$iscsi_iqn > /dev/null
fi
echo ""pool creation"" $OSname
ssh $xiv_system xcli.py pool_create pool=$OSname size=2000 snapshot_size=100 -y > /dev/null
size=30
for i in $(seq 1 $Lun_number) 
do
	ssh $xiv_system xcli.py vol_create pool=$OSname vol=$Hostname.$OSname-vol$i size=$size > /dev/null
	echo ""Lun creation"" $i
	size=$(($size+10))
done
for i in $(seq 1 $Lun_number)
do
	ssh $xiv_system  xcli.py map_vol host=$Hostname.$OSname vol=$Hostname.$OSname-vol$i lun=$i > /dev/null
	echo ""Lun mapping"" $i
done
ssh $xiv_system  xcli.py host_connectivity_list
ssh $xiv_system  xcli.py mapping_list
}
#
# Installing monitoring script
#
function XIV_Enable_Monitor {
echo "Enter XIV sysytem ip or name"
read xiv_system
scp /mnt/Interop/Scripts/monitor_xiv.sh $xiv_system:/local/scratch/
scp /mnt/Interop/Scripts/recover_xiv.sh $xiv_system:/local/scratch/
if [[ $? == 0 ]]
	then
	echo "monitor & recover script copy was ok"
else
	echo "monitor & recover script copy failed"
	exit
fi
echo "Enter the componenets you want to monitor, for example: module\|data\|Compression_Adapter\|Interface\|Flash_Enclosure\|Data_Reduction\|Vault_Device"
read components
echo $components
echo "Enter the cycle for the monitoring"
read cycle
echo ssh $xiv_system /local/scratch/monitor_xiv.sh "$components" "$cycle"
echo ssh $xiv_system /local/scratch/cat monitor.log
}

#
# Setting Up Performance configuration
#
function Performance_Setup {
echo "Enter required system type"
OPTIONS="xiv svc tms v7k" 
select sys_type in $OPTIONS
#free_systems=ssh stcon '/opt/FCCon/fcconnect.pl -dbop showfreestor |grep ' $sys_type
OPTIONS=`ssh stcon '/opt/FCCon/fcconnect.pl -dbop showfreestor |grep $sys_type|cut -f 1 -d ","'`
select target_system in $OPTIONS
print target_system
print "Listing existing zoning for $target_system"
`ssh stcon '/opt/FCCon/fcconnect.pl -op  -op CheckedZone -stor' $target_system`

}

scp /mnt/Interop/Scripts/monitor_xiv.sh $xiv_system:/local/scratch/
scp /mnt/Interop/Scripts/recover_xiv.sh $xiv_system:/local/scratch/
if [[ $? == 0 ]]
	then
	echo "monitor & recover script copy was ok"
else
	echo "monitor & recover script copy failed"
	exit
fi
echo "Enter the componenets you want to monitor, for example: module\|data\|Compression_Adapter\|Interface\|Flash_Enclosure\|Data_Reduction\|Vault_Device"
read components
echo $components
echo "Enter the cycle for the monitoring"
read cycle
echo ssh $xiv_system /local/scratch/monitor_xiv.sh "$components" "$cycle"
echo ssh $xiv_system /local/scratch/cat monitor.log

### main ###
# display the different options to the user to select from
OPTIONS="Remote_install Remote_Install_Specific Remote_Upgrade Build_and_Install_Code Build_HA_configuration Build_Mirror_configuration Host_Setup XIV_Host_Setup XIV_Enable_Monitor x"
select opt in $OPTIONS; do
	case $opt in 
		"Remote_install" )
		Remote_install
		;;
		"Remote_Install_Specific" )
		Remote_Install_Specific
		;;
		"Remote_Upgrade" )
		Remote_Upgrade
		;;
		"Build_and_Install_Code" )
		Build_and_Install_Code
		;;
		"Build_and_Install_Specific_Code" )
		Build_and_Install_Specific_Code
		;;
		"Build_HA_configuration" )
		Build_HA_configuration
		;;
		"Build_Mirror_configuration" )
		Build_Mirror_configuration
		;;
		"Host_Setup" )
		Host_Setup
		;;
		"XIV_Host_Setup" )
		XIV_Host_Setup
		;;
		"XIV_Enable_Monitor" )
		XIV_Enable_Monitor
		;;
		"x" )
		exit
		;;
		* )
		echo "Invalid option"
	esac
done
echo "kuku"
exit