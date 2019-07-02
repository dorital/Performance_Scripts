#!/bin/bash
#
# This script gets as input: system_name, active dataset and volume number. 
# This script has internal definitions of host_list, protocol, system clean, system setup.
# Then it creates basic vdbench output
#
#
# General Script Setup
to_clean_SC="no" 
to_setup_SC="yes"
sia_user="ibmsc"
sia_user_password="P@ssw0rd"
system_name="gen4d-pod-331"

function sc_clean {
echo "[INFO] Stopping Spectrum Connect service"
# stop service
ssh -t perf-proxy ssh perf-sc "service ibm_spectrum_connect stop"
# Uninstaling SC package 
sc_installed_package=`ssh -t perf-proxy ssh perf-sc "rpm -qa|grep ibm_spectrum_connect"`
ssh -t perf-proxy ssh perf-sc "rpm -ev $sc_installed_package"
#
}

function sc_setup {
echo "[INFO] Start Spectrum Connect setup"
# stop service
ssh -t perf-proxy ssh perf-sc "service ibm_spectrum_connect stop"
# modify the timeout settings and HA group name
#ssh perf-proxy ssh perf-sc su - ibmsc "sc_setting modify -n TOKEN_INACTIVITY_TIMEOUT -v 1440"
ssh perf-proxy ssh perf-sc su - ibmsc 'sh -c \"sc_setting modify -n  TOKEN_INACTIVITY_TIMEOUT -v 1440\"'
ssh perf-proxy ssh perf-SC su - ibmsc 'sh -c \"sc_setting modify -n SC_HA_GROUP -v ha_perf_vvol\"'
ssh perf-proxy ssh perf-SC su - ibmsc  "sc_setting list"
# modify the debug option for hsgsrv, vasa2,vasa3
ssh -t perf-proxy ssh perf-SC sed -i s/debug=False/debug=True/g /opt/ibm/ibm_spectrum_connect/conf.d/vasa3/vasa3_config.ini
ssh -t perf-proxy ssh perf-SC cat /opt/ibm/ibm_spectrum_connect/conf.d/vasa3/vasa3_config.ini
ssh -t perf-proxy ssh perf-SC sed -i s/debug=False/debug=True/g /opt/ibm/ibm_spectrum_connect/conf.d/vasa2/vasa2_config.ini
ssh -t perf-proxy ssh perf-SC cat /opt/ibm/ibm_spectrum_connect/conf.d/vasa2/vasa2_config.ini
ssh -t perf-proxy ssh perf-SC sed -i s/debug=False/debug=True/g /opt/ibm/ibm_spectrum_connect/conf.d/hsgsvr/hsgsvr_config.ini
ssh -t perf-proxy ssh perf-SC cat /opt/ibm/ibm_spectrum_connect/conf.d/hsgsvr/hsgsvr_config.ini
# start the vp service
ssh -t perf-proxy ssh perf-SC "service ibm_spectrum_connect start"
# Creating VP credentials 
ssh -t perf-proxy ssh perf-SC su - ibmsc 'sh -c \"sc_vasa_admin set_secret -n ibmsc -p P@ssw0rd\"'
echo "nu3?"
read nu
exit
# Create SSL certification
ssh -t perf-proxy ssh perf-SC su - ibmsc 'sh -c \"sc_ssl generate -c perf-sc -i 100.0.0.14 -e 3650 -n perf-sc\"'
# Reloading server certificate
# Create Storage System Credentials
ssh -t perf-proxy ssh perf-SC su - ibmsc 'sh -c \"sc_storage_credentials set -u ibmsc -p P@ssw0rd -a local\"'
# Change default admin credentials
ssh -t perf-proxy ssh perf-SC su - ibmsc 'sh -c \"sc_users change_password -n admin -p P@ssw0rd\"'
# Adding new storage array
# get system_ip
#verify the ibmsc user is already defined on the a9k system
ssh -t perf-proxy ssh perf-SC su - ibmsc 'sh -c \"sc_storage_array add -i $system_ip\"'
}


### main ###

echo "Script input parms are: "$@
echo "Script internal parms are:"
echo -e "to_clean_SC:\t"$to_clean_SC
echo -e "to_setup_SC:\t"$to_setup_SC
echo -e "system name:\t"$system_name
echo -e "press enter to continue"
read nu

#host_number=`echo ${#hostlist[@]}`

if [ $to_clean_SC == "yes" ];then
	echo "[INFO] Running system cleaning"
	sc_clean
else
	echo "[INFO] Not running system cleaning"
fi
#
if [ $to_setup_SC == "yes" ];then
	echo "[INFO] Running system setup"
	sc_setup
else
	echo "[INFO] Not running system setup"
fi
exit
#

