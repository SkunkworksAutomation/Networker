<#
POWERSHELL:    
    THIS CODE REQUIRE POWWERSHELL 7.x.(latest)    
    https://github.com/PowerShell/PowerShell/releases/tag/v7.3.4

    The Export-Clixml cmdlet encrypts credential objects by using the Windows Data Protection API. 
    The encryption ensures that only your user account on only that computer can decrypt the contents of the credential object. 
    The exported CLIXML file can't be used on a different computer or by a different user.    

    Export-Clixml only exports encrypted credentials on Windows. 
    On non-Windows operating systems such as macOS and Linux, credentials are exported as a plain text stored as a Unicode character array. 
    This provides some obfuscation but does not provide encryption.

    SOURCE: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/export-clixml?view=powershell-7.3
#>
$global:AuthObject = $null

function connect-nwapi {
    [CmdletBinding()]
    param (
        [Parameter( Mandatory=$true)]
        [string]$Server
    )
    begin {
        $exists = Test-Path -Path ".\$($Server).xml" -PathType Leaf
        if($exists) {
            $Credential = Import-CliXml ".\$($Server).xml"
        } else {
            $Credential = Get-Credential -Message "Please specify your Netowrker administrator credentials."
            $Credential | Export-CliXml ".\$($Server).xml"
        }
    }
    process {
     
        # BASE64 ENCODE USERNAME AND PASSWORD
        $base64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(
            ("{0}:{1}" -f $Credential.username,
                (
                    ConvertFrom-SecureString -SecureString $Credential.password -AsPlainText
                )
            )
        )
        )
        # CREATE THE AUTH OBJECT
        $object = @{
            server = "https://$($Server):9090/nwrestapi/v3/global"
            token = @{Authorization = "Basic $($base64)"}
        }
        $global:AuthObject = $object
        $global:AuthObject | Format-List
    }
}

function get-jobs {
    [CmdletBinding()]
    param (
        [Parameter( Mandatory=$true)]
        [array]$Filters
    )
    begin {}
    process {
        $Results = @()
        
        $Endpoint = "jobs"
    
        if($Filters.Length -gt 0) {
            $Join = ($Filters -join ' ') -replace '\s','%20' -replace '"','%22'
            $Endpoint = "$($Endpoint)?q=$($Join)"
        }

        $Query =  Invoke-RestMethod -Uri "$($AuthObject.server)/$($Endpoint)" `
        -Method GET `
        -ContentType 'application/json' `
        -Headers $AuthObject.token `
        -SkipCertificateCheck
        $Results = $Query.jobs

        return $Results
    }
}

function new-monitor {
    [CmdletBinding()]
    param (
        [Parameter( Mandatory=$true)]
        [string]$Link,
        [Parameter( Mandatory=$false)]
        [switch]$Mount
    )
    begin {}
    process {
        $Results = @()    
        
        If($Mount) {
            # MONITOR FOR A SESSION MOUNT
            Write-Host "[Networker]: Begining monitoring session for mount..." -ForegroundColor Yellow
            do{
                $Query =  Invoke-RestMethod -Uri "$($Link)" `
                -Method GET `
                -ContentType 'application/json' `
                -Headers $AuthObject.token `
                -SkipCertificateCheck

                if($Query.state -eq "Queued") {
                    Write-Host "[Networker]: STATE: $($Query.state)" -ForegroundColor Yellow
                    start-sleep -Seconds 5
                } 
                elseif($Query.state -eq "Active") {
                    Write-Host "[Networker]: STATE: $($Query.state), PROCESS: $($Query.vProxyMountState)"
                    start-sleep -Seconds 5
                }
                elseif($Query.state -eq "SessionActive" -and $Query.vProxyMountState -ne "Mounted") {
                    Write-Host "[Networker]: STATE: $($Query.state), PROCESS: $($Query.vProxyMountState)"
                    start-sleep -Seconds 5
                } else {
                    Write-Host "[Networker]: STATE: $($Query.state), PROCESS: $($Query.vProxyMountState)" -ForegroundColor green
                    $Results = $Query
                }
            }
            until($Query.state -eq "SessionActive" -and $Query.vProxyMountState -eq "Mounted")
        } else {
            # MONITOR FOR A RECOVERY SESSION
            Write-Host "[Networker]: Begining monitoring session for recovery..." -ForegroundColor Yellow
            do{
                $Query =  Invoke-RestMethod -Uri "$($Link)" `
                -Method GET `
                -ContentType 'application/json' `
                -Headers $AuthObject.token `
                -SkipCertificateCheck
                if($Query.state -eq "Queued") {
                    Write-Host "[Networker]: STATE: $($Query.state)" -ForegroundColor Yellow
                    start-sleep -Seconds 5
                } elseif($Query.state -eq "Active") {
                    Write-Host "[Networker]: STATE: $($Query.state)"
                    start-sleep -Seconds 5
                } else {
                    Write-Host "[Networker]: STATE: $($Query.state)" -ForegroundColor Green
                    $Results = $Query
                }
            }
            until($Query.state -eq "Completed")
        }

        return $Results
    }
}

function get-protectedvms {
    [CmdletBinding()]
    param (
        [Parameter( Mandatory=$true)]
        [array]$Filters
    )
    begin {}
    process {
        $Results = @()
        
        $Endpoint = "vmware/protectedvms"
    
        if($Filters.Length -gt 0) {
            $Join = ($Filters -join ' ') -replace '\s','%20' -replace '"','%22'
            $Endpoint = "$($Endpoint)?q=$($Join)"
        }

        $Query =  Invoke-RestMethod -Uri "$($AuthObject.server)/$($Endpoint)" `
        -Method GET `
        -ContentType 'application/json' `
        -Headers $AuthObject.token `
        -SkipCertificateCheck
        $Results = $Query.vms

        return $Results
    }
}

function get-backups {
    [CmdletBinding()]
    param (
        [Parameter( Mandatory=$true)]
        [string]$vCenter,
        [Parameter( Mandatory=$true)]
        [string]$Uuid,
        [Parameter( Mandatory=$true)]
        [array]$Filters
    )
    begin {}
    process {
        $Results = @()
        
        $Endpoint = "vmware/vcenters/$($vCenter)/protectedvms/$($Uuid)/backups"
    
        if($Filters.Length -gt 0) {
            $Join = ($Filters -join ' ') -replace '\s','%20' -replace '"','%22'
            $Endpoint = "$($Endpoint)?q=$($Join)"
        }

        $Query =  Invoke-RestMethod -Uri "$($AuthObject.server)/$($Endpoint)" `
        -Method GET `
        -ContentType 'application/json' `
        -Headers $AuthObject.token `
        -SkipCertificateCheck
        $Results = $Query.backups

        return $Results
    }
}

function new-vmmount {
    [CmdletBinding()]
    param (
        [Parameter( Mandatory=$true)]
        [string]$vCenter,
        [Parameter( Mandatory=$true)]
        [string]$Uuid,
        [Parameter( Mandatory=$true)]
        [string]$BackupId,
        [Parameter( Mandatory=$true)]
        [string]$InstanceId,
        [Parameter( Mandatory=$true)]
        [object]$Body

    )
    begin {}
    process {
              
        $Endpoint = "vmware/vcenters/$($vCenter)/protectedvms/$($Uuid)/backups/$($BackupId)/instances/$($InstanceId)/op/vmmount"
    
        Invoke-RestMethod -Uri "$($AuthObject.server)/$($Endpoint)" `
        -Method POST `
        -ContentType 'application/json' `
        -Headers $AuthObject.token `
        -Body ($Body | convertto-json -Depth 10) `
        -ResponseHeadersVariable RH `
        -SkipCertificateCheck

        return $RH
    }
}

function new-recover {
    [CmdletBinding()]
    param (
        [Parameter( Mandatory=$true)]
        [string]$vCenter,
        [Parameter( Mandatory=$true)]
        [string]$Uuid,
        [Parameter( Mandatory=$true)]
        [string]$BackupId,
        [Parameter( Mandatory=$true)]
        [string]$InstanceId,
        [Parameter( Mandatory=$true)]
        [object]$Body

    )
    begin {}
    process {
      
        $Endpoint = "vmware/vcenters/$($vCenter)/protectedvms/$($Uuid)/backups/$($BackupId)/instances/$($InstanceId)/op/recover"
    
        Invoke-RestMethod -Uri "$($AuthObject.server)/$($Endpoint)" `
        -Method POST `
        -ContentType 'application/json' `
        -Headers $AuthObject.token `
        -Body ($Body | convertto-json -Depth 10) `
        -ResponseHeadersVariable RH `
        -SkipCertificateCheck

        return $RH
    }
}