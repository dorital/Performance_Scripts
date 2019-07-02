#Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
Connect-VIServer  -server 100.0.0.13 -User "administrator@vsphere.local" -Password "P@ssw0rd"

# Must be defined before running the script
$Datastore = 'perf_vvol_ds_331'
$VMHost_array = @("100.0.0.21","100.0.0.22","100.0.0.23","100.0.0.24","100.0.0.25","100.0.0.26","100.0.0.27","100.0.0.28","100.0.0.29","100.0.0.30")
#$VMHost_array = @("100.0.0.25","100.0.0.26","100.0.0.27","100.0.0.28","100.0.0.29","100.0.0.30")
$delete_all = "yes"

if ($delete_all = "yes") {
    foreach ($VMHost in $VMHost_array) {
        $VMHost
        if ($VMHost -eq "100.0.0.10") {
            exit
        }
        else {
            "Stopping all VM on host: $VMHost"
#             get-vmhost -name $VMHost|get-vm|Stop-VM
            get-vmhost -name $VMHost|get-vm|Stop-VM -confirm:$false
#	        "Deleting all VM on host: $VMHost"
#             get-vmhost -name $VMHost|get-vm|Remove-VM -DeletePermanently
            get-vmhost -name $VMHost|get-vm|Remove-VM -DeletePermanently -confirm:$false
#             Start-Sleep -s 5
        }
    }
}
exit