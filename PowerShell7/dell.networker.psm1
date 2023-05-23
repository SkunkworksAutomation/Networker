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