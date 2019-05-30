<#
.Synopsis
   Summarizes TimeTaken from IIS logs for specified minute intervals
.DESCRIPTION
   Scripts gets the logs in the specified path summarizes all the logs.
.EXAMPLE
   .\summarize-TimeTaken -LogPath c:\IISLogs -IntervalMin 3 -CsvFullPath C:\temp\iis.csv -Verbose
#>

[CmdletBinding()]
Param(
[Parameter(Mandatory=$True)]
[string]$LogPath,
[Parameter(Mandatory=$True)]
[int]$IntervalMin,
[Parameter(Mandatory=$True)]
[string]$CsvFullPath
)
Import-Module PoshRSJob -verbose:$False

#$LogPath='C:\Users\emreg\Documents\customer\TURKCELLTFS\u_ex19052905\u_ex19052905.log'
Function Slice-Time {
[CmdLetBinding()]
Param(
[Parameter(Mandatory=$True)]
[int]$IntervalMin,
[Parameter(Mandatory=$True)]
[string]$DateToSlice
)
$SlicedMin=[Math]::Truncate(($DateToSlice -as [DateTime]).Minute / $IntervalMin) * $IntervalMin
($DateToSlice -replace ":\d+:\d+",":$($SlicedMin):00") -as [DateTime]
}
$ScriptStartTime=Get-Date

# Get the logs 
$logs=gci -Path $LogPath -File
Write-Verbose "[$(Get-date -Format G)] Working on $($Logs.Count) log files."
$starttime=Get-Date

# Prepare a script block that will parse
$ScriptBlock={$IISLog=get-content -Path ($_.FullName)
$Results = $IISlog -match ".+POST\s"
foreach ($Line in $Results) {

$Log=$line -split "\s"
#Fields: date time s-ip cs-method cs-uri-stem cs-uri-query s-port cs-username c-ip cs(User-Agent) cs(Referer) sc-status sc-substatus sc-win32-status time-taken
[PSCustomObject]@{
RequestDate="$($Log[0]) $($Log[1])" -as [DateTime]
SourceIP=$Log[2]
MethodName = $Log[3]
URI = $Log[4]
Query = $Log[5]
Port=$Log[6]
UserName=$Log[7]
ClientIP=$Log[8]
UserAgent=$Log[9]
Referrer=$Log[10]
Status=$Log[11]
SubStatus=$Log[12]
Win32Status=$Log[13]
TimeTaken=$Log[14]
}

} 
}
 
Write-Verbose "[$(Get-date -Format G)] Parsing IIS logs started"

# start running the script block multithreaded. Thread per Log file.
$AllResults=$logs | Start-RSJob -Name {$_.FullName} -ScriptBlock $ScriptBlock -Verbose:$false| Wait-RSJob -Verbose:$false| Receive-RSJob -Verbose:$false

Write-Verbose "[$(Get-date -Format G)] Parsing Duration is $((New-TimeSpan -Start $starttime -End (Get-Date)).TotalSeconds)"
$starttime=Get-Date
Write-Verbose "[$(Get-date -Format G)] Starting Slicing time"

# Do timeslicing using Slice-Time function and group based on the sliced time intervals.
$FilteredResult=$AllResults| ? Status -eq 200 | Select-Object SourceIP,URI,TimeTaken,@{Name="TimeInterval";Expression={Slice-Time -IntervalMin $IntervalMin -DateToSlice ($_.RequestDate)}} |Group-Object -Property URI,TimeInterval,SourceIP
Write-Verbose "[$(Get-date -Format G)] Slicing Duration is $((New-TimeSpan -Start $starttime -End (Get-Date)).TotalSeconds)"
$starttime=Get-Date
Write-Verbose "[$(Get-date -Format G)] Starting Aggregation"
$stats=$FilteredResult | % {
$Measure= $_.Group.TimeTaken| Measure-Object  -Minimum -Maximum -Average
$GroupArray=$_.Name -split ","
[PSCustomObject]@{
URI = $GroupArray[0]
TimeInterval=$GroupArray[1].TrimStart() -as [datetime]
SourceIP=$GroupArray[2].TrimStart()
SampleCount = $_.Count
Avg= [Math]::Round($Measure.Average)
Min = $Measure.Minimum
Max = $Measure.Maximum

}
}
Write-Verbose "[$(Get-date -Format G)] Aggreation Duration is $((New-TimeSpan -Start $starttime -End (Get-Date)).TotalSeconds)"
$starttime=Get-Date
Write-Verbose "[$(Get-date -Format G)] Starting to export to '$CsvFullPath'"
$stats | Export-Csv -Path $CsvFullPath -NoTypeInformation
Write-Verbose "[$(Get-date -Format G)] Export Duration is $((New-TimeSpan -Start $starttime -End (Get-Date)).TotalSeconds)"
Write-Verbose "[$(Get-date -Format G)] ScriptEnded. Script duration is $((New-TimeSpan -Start $ScriptStartTime -End (Get-Date)).TotalSeconds)"