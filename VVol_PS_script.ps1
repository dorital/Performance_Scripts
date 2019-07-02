Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
Connect-VIServer  -server 100.0.0.13 -User "administrator@vsphere.local" -Password "P@ssw0rd"

# Must be defined before running the script
#$Template = 'Isolated_vdbench.temp'
#$Datastore = 'datastore1'
$VMPattern = "vdbench-vm_"
#$Template = 'perf_vvol_vdbench.temp'
$Template = 'perf_vvol_vdbench_template'
$Datastore = 'perf_vvol_ds_331'
$VMHost_array = @("100.0.0.21","100.0.0.22","100.0.0.23","100.0.0.24","100.0.0.25","100.0.0.26","100.0.0.27","100.0.0.28","100.0.0.29")
$VMnetwork = "VM Network"
$Number_of_VM = 2
$vdisks_per_vm = 1
$vdisk_capacity = 16
$start_vm = "no"
# Loop example for array
#foreach ($element in $myArray) {
#	$element
#}

$OSCusSpec = 'RHEL74'
$Mask = "255.255.255.0"
$GW   = "192.168.1.254"
$DNS  = "192.168.1.1"

foreach ($VMHost in $VMHost_array) {
	$VMHost
	for ($vm=1; $vm -le $Number_of_VM; $vm++) {
		$VMName = $VMPattern+$VMHost+"_"+$vm
		"Creating new VM:" $VMName
		new-vm -name $VMName -template $Template -datastore $Datastore -vmhost $VMHost
# changing the VM network to VM network   
#		get-vm -name $VMName |Get-NetworkAdapter|Set-NetworkAdapter -networkname $VMnetwork -confirm:$false
# adding virtual disks
        for ($vdisk=1; $vdisk -le $vdisks_per_vm; $vdisk++) {
            New-HardDisk -vm $VMName -CapacityGB $vdisk_capacity -Persistence persistent
        }
        if ($start_vm -eq "yes") {
            "Starting VM:" $VMName 
            start-vm -vm $VMName
        }
	}
}
exit

For ($i=1; $i -le 10; $i++) {
#	$IP = "192.168.1." + (20+$i)
	$VMName = "rhel-vm" + "{0:00}" -f $i
#    "Create VM  " + "{0:00}" -f $i + " : " + $VMName + "- " + $IP
	Get-OSCustomizationSpec $OSCusSpec | Get-OSCustomizationNicMapping | Set-OSCustomizationNicMapping -IpMode UseStaticIP -IpAddress $IP -SubnetMask $Mask -DefaultGateway $GW

#"	New-VM -Name $VMName -Template $Template -VMHost $VMHost -Datastore $Datastore -OSCustomizationSpec $OSCusSpec"
	New-VM -Name $VMName -Template $Template -VMHost $VMHost -Datastore $Datastore -OSCustomizationSpec $OSCusSpec
	Start-VM  -VM $VMName
}
	#-RunAsync
exit 