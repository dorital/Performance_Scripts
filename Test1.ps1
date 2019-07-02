#Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
Connect-VIServer  -server 100.0.0.13 -User "administrator@vsphere.local" -Password "P@ssw0rd"

$Template = 'perf_vvol_vdbench_template'
$Datastore = 'perf_vvol_ds_331'
$VMHost = "100.0.0.21"
$VMName = "vdbench-vm_100.0.0.21_206"

Stop-VM -VM $VMName -Confirm:$false
if ($? -ne "True") {
    Get-Date -Format g
    "Stop VM $VMName failed, exiting"
}

#$task1 = Stop-VM -VM $VMName -Confirm:$false -RunAsync
#Wait-Task -Task $task1
#$task1 = Get-Task -Id $task1.Id
#$task1.State
#"end task1"

$task2 = Remove-VM -VM $VMName -DeletePermanently -confirm:$false -RunAsync
Wait-Task -Task $task2
$task2 = Get-Task -Id $task2.Id
$task2.State
"end task2"

$task3 = new-vm -name $VMName -template $Template -datastore $Datastore -vmhost $VMHost -RunAsync | Wait-Task
#Wait-Task -Task $task3
"end task3"

$task4 = start-vm -vm $VMName -RunAsync
Wait-Task -Task $task4
"end task4"

exit