Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
Connect-VIServer  -server 100.0.0.13 -User "administrator@vsphere.local" -Password "P@ssw0rd"

# Must be defined before running the script
$vm_pattern = "vdbench-vm_"
$vm_template = 'perf_vvol_vdbench_template'
$vm_datastore = 'vvol_ds_ba-55-nvme'
#$esxi_hosts_array = @("100.0.0.23")
#$esxi_hosts_array = @("100.0.0.21","100.0.0.22","100.0.0.23","100.0.0.24","100.0.0.25","100.0.0.26","100.0.0.27","100.0.0.28","100.0.0.29","100.0.0.30","100.0.0.31","100.0.0.32","100.0.0.33","100.0.0.34","100.0.0.35","100.0.0.36","100.0.0.37","100.0.0.38","100.0.0.39","100.0.0.40")
$esxi_hosts_array = @("100.0.0.21","100.0.0.22","100.0.0.23","100.0.0.24","100.0.0.25","100.0.0.26","100.0.0.27","100.0.0.28","100.0.0.29","100.0.0.30")
$vmnetwork = "VM Network"
$vm_per_esxi_host = 180
$vdisks_per_vm = 2
$vdisk_capacity = 2
$start_vm = "yes"

# For each ESXi host from the provided list do ...
Get-Date -Format g
foreach ($esxi_host in $esxi_hosts_array) {
	$esxi_host
# Create the desired number of VMs per each ESXi
	for ($vm=1; $vm -le $vm_per_esxi_host; $vm++) {
		$vm_name = $vm_pattern+$esxi_host+"_"+$vm
		"Creating new VM: $vm_name"
		new-vm -name $vm_name -template $vm_template -datastore $vm_datastore -vmhost $esxi_host
        if ($? -ne "True") {
            Get-Date -Format g
            "VM $vm_name creation failed, exiting"
            exit
        }
#        Start-Sleep -s 15
# Changing the VM network to VM network   
#		get-vm -name $vm_name |Get-NetworkAdapter|Set-NetworkAdapter -networkname $vmnetwork -confirm:$false
# For each VM add the defeind number of virtual disks with defined size
        for ($vdisk=1; $vdisk -le $vdisks_per_vm; $vdisk++) {
            New-HardDisk -vm $vm_name -CapacityGB $vdisk_capacity -Persistence persistent
            if ($? -ne "True") {
                Get-Date -Format g
                "Adding virtual disk to $vm_name failed, exiting"
                exit
            }
#            Start-Sleep -s 5
        }
        if ($start_vm -eq "yes") {
            "Starting VM: $vm_name" 
            start-vm -vm $vm_name
            if ($? -ne "True") {
                Get-Date -Format g
                "Starting $vm_name failed, exiting"
                exit
            }
#            Start-Sleep -s 5
        }
	}
}
Get-Date -Format g
exit