<#
.Synopsis
   Summarizes TimeTaken from IIS logs for specified minute intervals
.DESCRIPTION
   Scripts gets the logs in the specified path summarizes all the logs. Script Requires PoshRSJob Module to be installed.
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

#Requires -Modules PoshRSJob
#setting script start time
$ScriptStartTime=get-date
Import-Module PoshRSJob -verbose:$False

Function Slice-Time {
[CmdLetBinding()]
Param(
[Parameter(Mandatory=$True)]
[int]$IntervalMin,
[Parameter(Mandatory=$True)]
[DateTime]$DateToSlice
)
#determining which timeslot is $datetoslicein
$SlicedMin=[Math]::Truncate(($DateToSlice).Minute / $IntervalMin) * $IntervalMin
#creating a new dateobject with the determined timeslot above
[datetime]::new(($DateToSlice.Year),($DateToSlice.Month),($DateToSlice.Day),($DateToSlice.Hour),$SlicedMin,0)
}

# Get the logs 
$logs=gci -Path $LogPath -File
Write-Verbose "[$(Get-date -Format G)] Working on $($Logs.Count) log files."
$starttime=Get-Date

# Prepare a script block that will parse

$ScriptBlock = {

class Log {
[datetime]$RequestDate
[string]$SourceIP
[string]$MethodName
[string]$URI
[string]$Query
[int]$Port
[string]$UserName
[string]$ClientIP
[string]$UserAgent
[string]$Referrer
[int]$Status
[string]$SubStatus
[string]$Win32Status
[int]$TimeTaken
[datetime]$TimeInterval
}

$IISLog=get-content -Path ($_.FullName)

$StreamReader = New-object -TypeName System.IO.StreamReader -ArgumentList (Resolve-Path -Path $_.FullName -ErrorAction Stop).Path

while ($StreamReader.Peek() -ge 0)
{

$Line=$StreamReader.ReadLine()

if ($Line -match ".+POST\s") {
$Log=$Line -split "\s"
#Fields: date time s-ip cs-method cs-uri-stem cs-uri-query s-port cs-username c-ip cs(User-Agent) cs(Referer) sc-status sc-substatus sc-win32-status time-taken
$RequestDate="$($Log[0]) $($Log[1])" -as [DateTime]
[Log]@{
RequestDate= $RequestDate
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
TimeInterval=Slice-Time -IntervalMin $using:IntervalMin -DateToSlice $RequestDate
}
}

}
$StreamReader.Dispose()
}
 
Write-Verbose "[$(Get-date -Format G)] Parsing IIS logs started"

# start running the script block multithreaded. Thread per Log file.
$AllResults=$logs | Start-RSJob -Name {$_.FullName} -ScriptBlock $ScriptBlock -FunctionsToImport Slice-Time -Verbose:$false| Wait-RSJob -Verbose:$false| Receive-RSJob -Verbose:$false

Write-Verbose "[$(Get-date -Format G)] Parsing Duration is $((New-TimeSpan -Start $starttime -End (Get-Date)).TotalSeconds)"
$starttime=Get-Date
Write-Verbose "[$(Get-date -Format G)] Starting Slicing time"

# Do timeslicing using Slice-Time function and group based on the sliced time intervals.
$FilteredResult=$AllResults| ? Status -eq 200 | Select-Object SourceIP,URI,TimeTaken,TimeInterval |Group-Object -Property URI,TimeInterval,SourceIP
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
