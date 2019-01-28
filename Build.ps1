param ([string]$BuildID='xxxxx', [string]$Rollback='False',[string]$Product,[string]$Test = 'True')

Set-Location $PSScriptRoot

    #enter the ID of the build/release. This will appear in all the scripts being run as part of this build.

#$BuildID = "MAR-23"

    #enter the environment

#$Product = "Diamond"
#$Test = "False"
#$Rollback = "False"

    #The log file will be called Test, Build or Rollback based on the parameters

if ($Test -eq  'True')
{$LogFileNameBit = 'TEST_'}
else
{$LogFileNameBit = ''}

if ($Rollback -eq  'True')
{$LogFileNameBit2 = 'Rollback'}
else
{$LogFileNameBit2 = 'Build'}

    #set the name of the log file. This is the build/release ID puls the date and time. If this is a test run then amend the log file name

$LogFileName = 'Log_' + $LogFileNameBit + $LogFileNameBit2 + "_" + $BuildID + "_" +  $(get-date).ToString("yyyyMMdd_HHmmss") + ".txt"

    #then append the name of the log file to the path. This will always be C:\MarTechLog\ so it is a prerequiste of every environment that this folder exists

$LogFileNameFull = "C:\MarTechLog\" + $LogFileName

    if (Test-Path $LogFileNameFull) 
    {
      Remove-Item $LogFileNameFull
    }

    #create the empty log file

New-Item $LogFileNameFull | out-null 

    #Create an empty hashtable. This will hold script path and run order

$Scripts = @{}

    #initialise the Errored variable to 0

$Errored = 0

    #"--" + $BuildID

    #get every file that begins with the environment variable 


Get-ChildItem  -Filter $Product*.* | 

    #loop through each file

Foreach-Object {

   
        #get the contents of the file and put into a variable. At this point, it doesn't know which files need to be filtered. 

    $content = Get-Content $_.FullName
    
        #initialise the line variable

    $line = ""

        #get the lines from the file contents that match the buildID. Assign to the line variable

        #Write-Host 'Does BuildID equal Build00001' ($BuildID -eq 'Build00001')
        #$BuildID = 'Build00001'

    $content | Where-Object {$_ -match ("--" + $BuildID) -or $_ -eq "--Regression"} |  Set-Variable  "line" 

         
        #if the line variable is not empty (ie the file contains the release ID)...

    if ($line -ne "")
    {

        #then assign the path of the file to the Path variable

    $Path = $_.FullName

        #and find the position of the * which indicates where the release order is. 

    $PositionOfReleaseOrder = $line.IndexOf("*")

            #if PositionOfReleaseOrder is greater than 0...

        if ($PositionOfReleaseOrder -gt 0 )

        {

            #then get the number that follows the * and assign to the ReleaseOrder variable

        $ReleaseOrder = [int]$line.Substring($PositionOfReleaseOrder+1,2)
        }
        else

            #otherwise set the ReleaseOrder variable as 50

        {
        $ReleaseOrder = [int]"50"
        }

            #to the hash table, add the file path and release order

    $Scripts.add($_.FullName, $ReleaseOrder )   
    }
}

    #re-order the hash table by the "value" ie the release order 

$Scripts = $Scripts.GetEnumerator() | sort -Property value

    #for each row in the hash table...

ForEach ($d in $Scripts)
{

try
{

    #Write-Host $d.Key
    #try to run the contents of the file against the local database. If Rollback is true then only run the rollback script

    if (($Rollback -eq 'True' -and $d.Key -like '*rollback*') -or ($Rollback -eq 'False' -and $d.Key -notlike '*rollback*'))
    {
        if ($Test-eq 'True')
        {
            Add-Content $LogFileNameFull ($d.Key + " - Not Run")
        }
        else
        {
            if ($env:USERNAME -eq 'DBA')
                {$InstanceName = "DESKTOP-CGRB0T0\LIVE" }
            elseif ($env:USERNAME -eq 'Developer')
                {$InstanceName = "DESKTOP-CGRB0T0\DEVELOPMENT2"}
            else {$InstanceName = "(local)"}
        
            $FullFileName = $d.Key
            $FileExtension =  $FullFileName.Substring($FullFileName.IndexOf(".")+1,3)
            if ($FileExtension -eq 'sql' -or $FileExtension -eq 'ps1')
                {
                if ($FileExtension -eq 'sql')
                    {
                    $StringArray = "BuildID='$BuildID '"
                    Write-Host $StringArray
                    Invoke-Sqlcmd -InputFile $d.Key -ServerInstance $InstanceName -ErrorAction Stop -Variable $StringArray
                     }
                else
                    {
                    $ErrorActionPreference = 'Stop'
                    &$FullFileName 
                    $ErrorActionPreference = 'Continue'
                    }
                Add-Content $LogFileNameFull ($d.Key + " - Succeeded")
                }
          }
   }

}
catch
{
    #if it fails then increment the Errored variable and add the error message to the log file

$Errored = $Errored + 1
Add-Content $LogFileNameFull ($d.Key + " " + $_) 

}
}

    #if there are no errors then add success to the log file

if ($Errored -eq 0)
{
$SuccessMessage = $LogFileNameBit2 + " was successful"
Add-Content $LogFileNameFull $SuccessMessage
}

 #now check if the build passed testing, if not rollback or testing

if($Rollback -eq 'False' -and $Test -eq 'False')
{
$SQL = "use Diamond select cast(ad.checktest('" + $BuildID + "') as int) Result"

$QueryResult = ''


$QueryResult = Invoke-Sqlcmd -ServerInstance $InstanceName -Database 'Diamond' -Query $SQL 


$QueryResultColumn = $QueryResult.Result

if ($QueryResultColumn -eq 1)
{$TestResult = 'All testing passed'}
elseif ($QueryResultColumn -eq 0)
{$TestResult = 'Testing failed'}
elseif ($QueryResultColumn -eq -1)
{$TestResult = 'No test rows'}

Add-Content $LogFileNameFull $TestResult
}