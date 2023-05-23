Import-Module .\dell.networker.psm1 -Force
<#
    NETWORKER:
        $hours = how far back in hours we want to look
        $jobtype = the type of job we are looking for
        $networker = fqdn of the networker server we want to query

        DOCUMENTATION: https://developer.dell.com/apis/2378/versions/v3/reference/swagger.json/paths/~1jobs/get
#>

# VARS
[int]$hours = 24
[string]$jobtype = "save job"
[string]$networker = 'nve-01.vcorp.local'

connect-nwapi -Server $networker

$Filters = @(
    "startTime:[`"$($hours) hours`"]",
    "and type:`"$($jobtype)`"",
    "and completionStatus:Failed"
)

$jobs = get-jobs -Filters $Filters

$jobs | `
select-object clientHostname,type,completionStatus,state,startTime,endTime | `
sort-object clientHostname | `
format-table -AutoSize