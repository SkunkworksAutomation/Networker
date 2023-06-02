Import-Module .\dell.networker.psm1 -Force
<#
    NETWORKER:
        $networker = fqdn of the networker server we want to query
        $sourcename = vm that will source the flr
        $targetname = vm that the flr will land on
        $recoverme = path/file on the source vm
        $recoverto = path on the target vm   
#>

# VARS
[string]$networker = 'nve-01.vcorp.local'

# VIRTUAL MACHINES
[string]$sourcename = 'vc1-ubu-01'
[string]$recoverme = "/home/vcorp/myfile.txt"

[string]$targetname = 'vc1-ubu-02'
[string]$recoverto = "/home/vcorp/"

# CREDENTIALS FOR TARGET VIRTUAL MACHINE
$exists = Test-Path .\virtualmachines.xml -PathType Leaf
if($exists) {
    $Credential = Import-Clixml .\virtualmachines.xml
} else {
    $Credential = Get-Credential `
    -Message "Specify administrator credentials for the target virtual machine."
    $Credential | Export-Clixml .\virtualmachines.xml
}

# SETUP CONNECTION TO THE NETWORKER API
connect-nwapi -Server $networker

Write-Host "[Networker]: Begining File Level Recovery...
==> Source VM: $($sourcename)
==> Recovering: $($recoverme)
==> Target VM: $($targetname )
==> Recovering to: $($recoverto)
"

# GET THE SOURCE & TARGET VMs FOR THE FLR
$Filters = @(
    "hostname:$($sourcename),$($targetname)"
)
$vms = get-protectedvms -Filters $Filters

# SELECT THE SOURCE VM
$source = $vms | `
where-object {$_.hostname -eq $sourcename}

# SELECT THE TARGET VM
$target = $vms | `
where-object {$_.hostname -eq $targetname}

# GET SOURCE VM BACKUPS BETWEEN A DATE RANGE
$Filters = @(
    "saveTime:['2023-05-31T00:00:01' TO '2023-05-31T23:59:59']"
)
$backups = get-backups `
-vCenter $source.vCenterHostname `
-Uuid $source.uuid `
-Filters $Filters

# SELECT THE LATEST BACKUP
$backup = $backups | sort-object creationTime -Descending | select-object -first 1 
$instance = $backup.instances | where-object {$_.clone -eq $false}

# DECRYPT THE PASSWORD
$Decrypt = $(
    ConvertFrom-SecureString `
    -SecureString $Credential.password `
    -AsPlainText
)

# BUILD THE REQUEST BODY
$Body = [ordered]@{
    installFlrAgent = $true
    targetVCenterHostname = $source.vCenterHostname
    targetVmAdminUserId = $Credential.UserName
    targetVmAdminUserPassword = $Decrypt
    targetVmName = $target.hostname
    targetVmMoref = $target.morefId
    targetVmUserId = $Credential.UserName
    targetVmUserPassword = $Decrypt
    uninstallFlrAgent = $true
    vProxy = $source.vProxyUsedForLastBackup
}

$vmmount = new-vmmount `
-vCenter $source.vCenterHostname `
-Uuid $source.uuid `
-BackupId $backup.id `
-InstanceId $instance.id `
-Body $Body

# MONITOR UNTIL MOUNTED
$monitor = new-monitor -Link $vmmount.Location -Mount
$monitor.message
Write-Host

# PARSE THE JOB ID
$job = $vmmount.Location -split '/jobs/' | select-object -last 1

# BUILD THE REQUEST BODY
$Body = [ordered]@{
    recoverMode = "FLR"
    vCenterHostname = $source.vCenterHostname
    mountJobId = "$($job)"
    vmwareVmFlrOptions = @{
        terminateMountSession = $true
        overwrite = $true
        itemsToRecover = @(
            "$($recoverme)"
        )
        recoveryDestination = $recoverto
    }
}

$vmrecover = new-recover `
-vCenter $source.vCenterHostname `
-Uuid $source.uuid `
-BackupId $backup.id `
-InstanceId $instance.id `
-Body $Body

# MONITOR UNTIL COMPLETED
$monitor = new-monitor -Link $vmrecover.Location
$monitor.message -split '\n'| select-object -last 2
Write-Host