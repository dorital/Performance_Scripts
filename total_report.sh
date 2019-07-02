#!/bin/bash
#
# This script gets as input: system_name, RACE_build and if it is master or side branch. 
# it will copy the required RACE code to the specific system and install it. 
#
#
# General Script Setup
#
# VVol reports
# Creating a report from totals report
#extracting the results
#cat totals.html |grep "avg" |awk '{{for(i=3;i<=NF;i++) printf $i" "} print ""; }' >totals.txt
#extracting the end time
#cat totals.html |grep "avg"|awk '{print $1}'
#extracting the end time + the results in one line
#cat totals.html |grep "avg" |awk '{printf $1" "; {for(i=3;i<=NF;i++) printf $i" "} print ""; }' >totals.txt
results_path="/PerfResults/"
results_dir="${1}/"
total_filename="${results_path}${results_dir}totals.html"
echo $total_filename
#records=`cat ${results_dir}totals.html |grep "RD=\|avg"`
echo "`date +%F_%H%M` [INFO] Start - collecting total results"
current_date=`date +%F_%H%M`
results="${results_path}${results_dir}results_${current_date}.csv"
echo $results
rm -f ${results}
while read -r line; do
    rec="$line"
    if [[ `echo $rec|grep "RD="` ]];then
        test=`echo $rec |awk -F";" '{print $1}'|awk -F"RD=" '{print $2}'`
        echo -n $test" " >> ${results}
    elif [[ `echo $rec|grep "avg"` ]];then
        echo $rec |awk '{printf $1" "; {for(i=3;i<=NF;i++) printf $i" "} print ""; }' >> ${results}
    fi


#done
done < "$total_filename"

    