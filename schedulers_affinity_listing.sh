#!/bin/sh
#
# This script get as input a system name and then lists the PIDs for interface threads, TxN threads and DRN threads 
#
#
if [ $# != 1 ];then
	echo "sample: $0 system_name"
	exit
fi
system_name=$1
echo "System name:" $system_name
drn=0
txn=0
fc=0
iscsi=0
inode=0
for pid in `ssh $system_name top -b -n1 -H|awk '/MN/ {print$1}'`;do
	thread_name=`ssh $system_name top -b -n1 -p $pid|awk '/MN/ {print$12}'`
	echo "pid $pid for $thread_name `ssh $system_name taskset -pc $pid`"
	((drn++))
done
echo "Total DRN schedulers: $drn"
#
for pid in `ssh $system_name top -b -n1 -H|awk '/SST/ {print$1}'`;do
	thread_name=`ssh $system_name top -b -n1 -p $pid|awk '/SST/ {print$12$13}'`
	echo "pid $pid for $thread_name `ssh $system_name taskset -pc $pid`"
	((txn++))
done
echo "Total TxN schedulers: $txn"
for pid in `ssh $system_name top -b -n1 -H|awk '/fc-port-/ {print$1}'`;do
	thread_name=`ssh $system_name top -b -n1 -p $pid|awk '/fc-port-/ {print$12$13}'`
	echo "pid $pid for $thread_name `ssh $system_name taskset -pc $pid`"
	((fc++))
done
echo "Total FC schedulers: $fc"
for pid in `ssh $system_name top -b -n1 -H|awk '/xis_device/ {print$1}'`;do
	thread_name=`ssh $system_name top -b -n1 -p $pid|awk '/xis_device/ {print$12$13}'`
	echo "pid $pid for $thread_name `ssh $system_name taskset -pc $pid`"
	((iscsi++))
done
echo "Total iSCSI schedulers: $iscsi"
for pid in `ssh $system_name top -b -n1 -H|gawk '/\<worker\>/ {print$1}'`;do
	thread_name=`ssh $system_name top -b -n1 -p $pid|gawk '/\<worker\>/ {print$12$13}'`
	echo "pid $pid for $thread_name `ssh $system_name taskset -pc $pid`"
	((inode++))
done
echo "Total i_node schedulers: $inode"
exit
