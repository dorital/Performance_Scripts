# VVol reports
# Creating a report from totals report
#extracting the results
cat totals.html |grep "avg" |awk '{{for(i=3;i<=NF;i++) printf $i" "} print ""; }' >totals.txt
#extracting the end time
cat totals.html |grep "avg"|awk '{print $1}'
#extracting the end time + the results in one line
cat totals.html |grep "avg" |awk '{printf $1" "; {for(i=3;i<=NF;i++) printf $i" "} print ""; }' >totals.txt
