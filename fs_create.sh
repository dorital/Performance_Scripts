#modify setup scrip with relevant $OS_name by issuing - sed 's/$OS_name/<enter_new_$OS_name>/gw h$OS_namet_setup.sh' $server_name_setup.sh 
multipath -ll
echo "enter number of fs to create"
read num_fs
for i in $(seq 1 $num_fs)
do
    echo "enter path to be used for fs creation, for example: mpatha"
    read mpath
    echo $mpath
    echo "enter ext3 or ext4"
    read ext
    echo $ext
    pvcreate /dev/mapper/$mpath
    vgcreate vg_$mpath  /dev/mapper/$mpath
    lvcreate -l 100%VG -n lv_$mpath vg_$mpath
    mkfs.$ext /dev/mapper/vg_$mpath-lv_$mpath
    mkdir -p /mnt/$mpath/fs_$ext/
    mount /dev/mapper/vg_$mpath-lv_$mpath /mnt/$mpath/fs_$ext/
    #For space reclaim use “–o discard” to the mount command 
    #mount –o discard  /dev/mapper/vg_mpathX-lv_mpathX /mnt/mpathX/fs_ext4/
done
mount

hostlist=(rmhost10 rmhost6)

### main ###
if [ $# != 3 ];then
	echo "sample: $0 system_name active_dataset_size_GB vol_number"
	exit
fi
system_name=$1
active_dataset=$2
vol_number=$3
#

system_serial=`ssh $system_name xcli.py config_get |grep system_id |awk '{print $2}'`
system_serial_hex=`echo "obase=16; $system_serial"|bc`
for host in "${hostlist[@]}";do
	echo "[INFO] Start - Creating partition and FS on host $host"
	for mpath in `ssh $host multipath -ll |grep -i 35d4|awk '{print $1}'`;do
		ssh $host echo -e "n\np\n1\n\n\nw" | fdisk /dev/mapper/${mpath}
		ssh $host echo -e "x\nb\n63\nw" | fdisk /dev/mapper/${mpath}
		ssh $host mkfs.ext3 /dev/mapper/${mpath} 
		ssh $host mkdir /mnt/${mpath} 
		ssh $host mount /dev/mapper/${mpath}1 /mnt/${mpath}
		ssh $host touch /mnt/${mpath}/vdbench.test.file 
		# use the file path in vdbench
	done
done
