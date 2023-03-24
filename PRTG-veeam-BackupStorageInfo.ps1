<#
    .SYNOPSIS
    PRTG push veeam Backup Storage info

    .DESCRIPTION
    If no RepoName is set - Advanced Sensor will report SizeByte, FreeSpaceByte and PercentFree
    If a RepoName is set - Advanced Sensor will report all info (Name, SizeByte, FreeSpaceByte, UsedSpaceByte, PercentFree, PercentUsed)

    .EXAMPLE
    PS> PRTG-veeam-BackupStorage.ps1

    .EXAMPLE
    PS> PRTG-veeam-BackupStorage.ps1 -RepoName 'my test repo'

    .PARAMETER probeIP
    The IP or FQDN of your PRTG Probe

    .PARAMETER sensorPort
    The Port which the Probe listens to push. Default 5050

    .PARAMETER senosrKey
    The Key for the Push Sensor

    .PARAMETER RepoName
    Specify the RepoName you want to push to PRTG

    .PARAMETER DryRun
    If set, the result will not be pushed to PRTG and will output some more info
    
    .NOTES
    +---------------------------------------------------------------------------------------------+ 
    | ORIGIN STORY                                                                                |
    +---------------------------------------------------------------------------------------------| 
    |   DATE        : 2023.03.24                                                                  |
    |   AUTHOR      : TS-Management GmbH, Stefan Mueller                                          | 
    |   DESCRIPTION : PRTG Push Veeam Backup Repositoriy free Size %                              |
    +---------------------------------------------------------------------------------------------+   

    +---------------------------------------------------------------------------------------------+ 
    | HISTORY                                                                                     |
    +---------------------------------------------------------------------------------------------| 
    |   2023.03.24 - Initial Version                                                              |
    +---------------------------------------------------------------------------------------------+      

    .LINK
    https://ts-man.ch

#>

[cmdletbinding()]
param(
    [Parameter(Mandatory=$true)] [string] $probeIP = "127.0.0.1",
    [parameter(Mandatory=$true)] [string] $sensorPort = "5050",
    [parameter(Mandatory=$true)] [string] $sensorKey,
    [Parameter(Mandatory=$false)] [switch] $DryRun = $false,
    [Parameter(Mandatory=$false)] [string] $RepoName
)

#region: Config
$LimitWarnFreeByte = 1GB
$LimitErrFreeByte = 0.5GB
$LimitFreeByte = 0              # 0 = Disable PRTG Warnings | 1 = Enable PRTG Warnings

$LimitWarnFreePercent = 20
$LimitErrFreePercent = 10
$LimitFreePercent = 1           # 0 = Disable PRTG Warnings | 1 = Enable PRTG Warnings

$LimitWarnUsedByte = 100TB
$LimitErrUsedByte = 100TB
$LimitUsedByte = 0              # 0 = Disable PRTG Warnings | 1 = Enable PRTG Warnings

$LimitWarnUsedPercent = 80
$LimitErrUsedPercent = 90
$LimitUsedPercent  = 0          # 0 = Disable PRTG Warnings | 1 = Enable PRTG Warnings

#####  CONFIG END  #####






#endregion

#region: requirements
# check if veeam powershell snapin is loaded. if not, load it
if( (Get-PSSnapin -Name veeampssnapin -ErrorAction SilentlyContinue) -eq $nul){
    Add-PSSnapin veeampssnapin -ErrorAction SilentlyContinue
}
#endregion

### Push to PRTG ###
function sendPush(){
    Add-Type -AssemblyName system.web

    if($DryRun){
        write-host "result"-ForegroundColor Green
        write-host $prtgresult 
    }

    #$Answer = Invoke-WebRequest -Uri $NETXNUA -Method Post -Body $RequestBody -ContentType $ContentType -UseBasicParsing
    $answer = Invoke-WebRequest `
       -method POST `
       -URI ($probeIP + ":" + $sensorPort + "/" + $sensorKey) `
       -ContentType "text/xml" `
       -Body $prtgresult `
       -usebasicparsing

    if ($answer.statuscode -ne 200) {
       write-warning "Request to PRTG failed"
       write-host "answer: " $answer.statuscode
       exit 1
    }
    else {
        #write-host "Request to PRTG OK"
        #write-host $answer.content
        return $answer.content | convertFrom-json
       
    }
}

#region: get repos and size
$Repos = get-vbrbackuprepository
$RepoDetails = foreach ($repo in $Repos) {
    [PSCustomObject]@{
        'Name'          = $Repo.Name
        'ID'            = $Repo.ID
        'SizeByte'      = $Repo.GetContainer().CachedTotalSpace.InBytes
        'FreeSpaceByte' = $Repo.GetContainer().CachedFreeSpace.InBytes
        'UsedSpaceByte' = $Repo.GetContainer().CachedTotalSpace.InBytes - $Repo.GetContainer().CachedFreeSpace.InBytes
        'PercentFree'   = 100 / $Repo.GetContainer().CachedTotalSpace.InBytes * $Repo.GetContainer().CachedFreeSpace.InBytes
        'PercentUsed'   = 100 / $Repo.GetContainer().CachedTotalSpace.InBytes * ($Repo.GetContainer().CachedTotalSpace.InBytes - $Repo.GetContainer().CachedFreeSpace.InBytes)
    }
} 
#endregion

#region: generate final RepoDetails, depending if RepoName is set or not
if($RepoName){
    if($RepoName -in $RepoDetails.Name){
        $repo = $RepoDetails | Where-Object {$_.name -eq $RepoName}
        $RepoDetails = $repo
    }else{
        write-host "repo dos not exist in" -ForegroundColor Red
        Exit 1
    }
}

if($DryRun){
    write-host "final Repo Detials" -ForegroundColor Yellow -NoNewline
    $RepoDetails
}
#endregion


#region: create xml for all Repos

#region: PRTG XML Header
$prtgresult = @"
<?xml version="1.0" encoding="UTF-8" ?>
<prtg>

"@
#endregion

# XMP for all REPOS

foreach($repo in $RepoDetails){
    $rName     = $repo.Name
    $rSizeByte = [System.Math]::Round($repo.SizeByte,2)
    $rFreeByte = [System.Math]::Round($repo.FreeSpaceByte,2)
    $rFreeP    = [System.Math]::Round($repo.PercentFree,2)

    if(!$RepoName){
        $chanSize        = "$rName | Size"
        $chanFreeByte    = "$rName | Free GB"
        $chanFreePercent = "$rName | Free Percent"
    }else{
        $chanSize        = "Size"
        $chanFreeByte    = "Free GB"
        $chanFreePercent = "Free Percent"
    }
$prtgresult += @"
    <result>
        <channel>$chanSize</channel>
        <value>$rSizeByte</value>
        <VolumeSize>GigaByte</VolumeSize>
        <showChart>1</showChart>
        <showTable>1</showTable>
        <float>1</float>
    </result>
    <result>
        <channel>$chanFreeByte</channel>
        <VolumeSize>GigaByte</VolumeSize>
        <mode>Absolute</mode>
        <float>1</float>
        <value>$rFreeByte</value>
        <showChart>1</showChart>
        <showTable>1</showTable>
        <LimitMinWarning>$LimitWarnFreeByte</LimitMinWarning>
        <LimitMinError>$LimitErrFreeByte</LimitMinError>
        <LimitWarningMsg>Quota nearly used</LimitWarningMsg>
        <LimitErrorMsg>Quota over used</LimitErrorMsg>
        <LimitMode>$LimitFreeByte</LimitMode>
    </result>
    <result>
        <channel>$chanFreePercent</channel>
        <float>1</float>
        <unit>Percent</unit>
        <value>$rFreeP</value>        
        <showChart>1</showChart>
        <showTable>1</showTable>
        <LimitMinWarning>$LimitWarnFreePercent</LimitMinWarning>
        <LimitMinError>$LimitErrFreePercent</LimitMinError>
        <LimitWarningMsg>$LimitWarnFreePercent% Quota used</LimitWarningMsg>
        <LimitErrorMsg>$LimitErrFreePercent% Quota used</LimitErrorMsg>
        <LimitMode>$LimitFreePercent</LimitMode>
    </result>


"@        
}

# XML for specified REPO
if($RepoName){
    $rUsedByte = [System.Math]::Round($RepoDetails.UsedSpaceByte,2)
    $rUsedP    = [System.Math]::Round($RepoDetails.PercentUsed,2)

$prtgresult += @"
    <result>
        <channel>Used Byte</channel>
        <value>$rUsedByte</value>
        <float>1</float>
        <VolumeSize>GigaByte</VolumeSize>
        <showChart>1</showChart>
        <showTable>1</showTable>
        <LimitMaxWarning>$LimitWarnUsedByte</LimitMaxWarning>
        <LimitMaxError>$LimitErrUsedByte</LimitMaxError>
        <LimitWarningMsg>Quota nearly used</LimitWarningMsg>
        <LimitErrorMsg>Quota over used</LimitErrorMsg>
        <LimitMode>$LimitUsedByte</LimitMode>
    </result>
    <result>
        <channel>Used Percent</channel>
        <value>$rUsedP</value>
        <unit>Percent</unit>
        <float>1</float>
        <showChart>1</showChart>
        <showTable>1</showTable>
        <LimitMaxWarning>$LimitWarnUsedPercent</LimitMaxWarning>
        <LimitMaxError>$LimitErrUsedPercent</LimitMaxError>
        <LimitWarningMsg>$LimitWarnUsedPercent% Quota used</LimitWarningMsg>
        <LimitErrorMsg>$LimitErrUsedPercent% Quota used</LimitErrorMsg>
        <LimitMode>$LimitUsedPercent</LimitMode>
    </result>    

<text>$RepoName</text>
"@
}

#region: PRTG XML Footer
$prtgresult += @"
</prtg>
"@
#endregion

#endregion


if($DryRun){
    if($log){
        writeLog "*** Dryrun"
    }
    write-host $prtgresult
}else{
    if($log){
        writeLog "*** SendPush"
        writeLog $prtgresult
    }
<#
    write-host "matching"
    $answer.'Matching Sensors'
#>
    $sendPushCntr = 1
    
    while($(sendPush).'Matching Sensors' -ne 1){
        Write-Host "No Matching Sensor found. Retry" $sendPushCntr -ForegroundColor yellow

        if($sendPUshCntr -eq 11){
            write-host "No matching sensor found" -ForegroundColor Red
            exit 1
        }
        #sendPush
        $sendPushCntr ++
        sleep -seconds 10

    }

    write-host "matching sensor found" -ForegroundColor green
    
}

sleep -Seconds 3