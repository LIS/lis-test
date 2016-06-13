########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################
<#
.Synopsis
    Disable and Enable Key-Value Pair Exchange serice and Verify the basic KVP read operations work.
.Description
    Disable, then re-enable the LIS Exchange service.  and then
    verify basic KVP read operations can be performed by reading
    intrinsic data from the VM.  Additionally, check that three
    keys are part of the returned data.

    A typical test case definition for this test script would look
    similar to the following:
        <test>
            <testName>VerifyItegratedExchangeService</testName>
            <testScript>SetupScripts\INST_LIS_ExchangeService.ps1/testScript>
            <timeout>600</timeout>
            <onError>Continue</onError>
            <noReboot>True</noReboot>
            <testparams>
                <param>rootDir=D:\lisa\trunk\lisablue</param>
                <param>TC_COVERED=KVP-10</param>
            </testparams>
        </test>
.Parameter vmName
    Name of the VM to read intrinsic data from.
.Parameter hvServer
    Name of the Hyper-V server hosting the VM.
.Parameter testParams
    Test data for this test case
.Example
    setupScripts\INST_LIS_ExchangeService.ps1 -vmName "myVm" -hvServer "localhost -TestParams "rootDir=c:\lisa\trunk\lisa;TC_COVERED=KVP-10"
.Link
    None.
#>

param([String] $vmName, [String] $hvServer, [String] $testParams)
#######################################################################
#
# KvpToDict
#
#######################################################################
function KvpToDict($rawData)
{
    <#
    .Synopsis
        Convert the KVP data to a PowerShell dictionary.
    .Description
        Convert the KVP xml data into a PowerShell dictionary.
        All keys are added to the dictionary, even if their
        values are null.
    .Parameter rawData
        The raw xml KVP data.
    .Example
        KvpToDict $myKvpData
    #>

    $dict = @{}

    foreach ($dataItem in $rawData)
    {
        $key = ""
        $value = ""
        $xmlData = [Xml] $dataItem
        
        foreach ($p in $xmlData.INSTANCE.PROPERTY)
        {
            if ($p.Name -eq "Name")
            {
                $key = $p.Value
            }

            if ($p.Name -eq "Data")
            {
                $value = $p.Value
            }
        }
        $dict[$key] = $value
    }

    return $dict
}

#######################################################################
#
# Main script body
#
#######################################################################
#
# Make sure the required arguments were passed
#
if (-not $vmName)
{
    "Error: no VMName was specified"
    return $False
}

if (-not $hvServer)
{
    "Error: No hvServer was specified"
    return $False
}

if (-not $testParams)
{
    "Error: No test parameters specified"
    return $False
}
#
# Debug - display the test parameters so they are captured in the log file
#
Write-Output "TestParams : '${testParams}'"

Del $summaryLog -ErrorAction SilentlyContinue
$summaryLog  = "${vmName}_summary.log"
#
# Parse the test parameters
#
$rootDir = $null
$intrinsic = $True

$params = $testParams.Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    switch ($fields[0].Trim())
    {      
    "nonintrinsic" { $intrinsic = $False }
    "rootdir"      { $rootDir   = $fields[1].Trim() }
    "TC_COVERED"   { $tcCovered = $fields[1].Trim() }
    default  {}       
    }
}

if (-not $rootDir)
{
    "Warn : no rootdir was specified"
}
else
{
    cd $rootDir
}

echo "Covers : ${tcCovered}" >> $summaryLog
#
# Verify the Data Exchange Service is enabled for this VM
#
$des = Get-VMIntegrationService -vmname $vmName -ComputerName $hvServer
if (-not $des)
{
    "Error: Unable to retrieve Integration Service status from VM '${vmName}'"
    return $False
}

#
#Disable the Key-Value Pair Exchange
#

"Info : Disabling the Integrated Services Shutdown Service"

Disable-VMIntegrationService -ComputerName $hvServer -VMName $vmName -Name "Key-Value Pair Exchange"
$status = Get-VMIntegrationService -ComputerName $hvServer -VMName $vmName -Name "Key-Value Pair Exchange"
if ($status.Enabled -ne $False)
{
    "Error: Key-Value Pair Exchange could not be disabled"
    return $False
}

if ($status.PrimaryOperationalStatus -ne "Ok")
{
    "Error: Incorrect Operational Status for Key-Value Pair Exchange Service: $($status.PrimaryOperationalStatus)"
    return $False
}
"Info : Integrated Key-Value Pair Exchange Service successfully disabled"

#
# Enable the Shutdown service
#
"Info : Enabling the Integrated Services Key-Value Pair Exchange Service"

Enable-VMIntegrationService -ComputerName $hvServer -VMName $vmName -Name "Key-Value Pair Exchange"
$status = Get-VMIntegrationService -ComputerName $hvServer -VMName $vmName -Name "Key-Value Pair Exchange"
if ($status.Enabled -ne $True)
{
    "Error: Integrated Key-Value Pair Exchange Service could not be enabled"
    return $False
}

if ($status.PrimaryOperationalStatus -ne "Ok")
{
    "Error: Incorrect Operational Status for Key-Value Pair Exchange Service: $($status.PrimaryOperationalStatus)"
    return $False
}
"Info : Integrated Key-Value Pair Exchange Service successfully Enabled"


#
# Create a data exchange object and collect KVP data from the VM
#
$Vm = Get-WmiObject -ComputerName $hvServer -Namespace root\virtualization\v2 -Query "Select * From Msvm_ComputerSystem Where ElementName=`'$VMName`'"
if (-not $Vm)
{
    "Error: Unable to the VM '${VMName}' on the local host"
    return $False
}

$Kvp = Get-WmiObject -ComputerName $hvServer -Namespace root\virtualization\v2 -Query "Associators of {$Vm} Where AssocClass=Msvm_SystemDevice ResultClass=Msvm_KvpExchangeComponent"
if (-not $Kvp)
{
    "Error: Unable to retrieve KVP Exchange object for VM '${vmName}'"
    return $False
}

if ($Intrinsic)
{
    "Intrinsic Data"
    $kvpData = $Kvp.GuestIntrinsicExchangeItems
}
else
{
    "Non-Intrinsic Data"
    $kvpData = $Kvp.GuestExchangeItems
}

$dict = KvpToDict $kvpData
#
# Write out the kvp data so it appears in the log file
#
foreach ($key in $dict.Keys)
{
    $value = $dict[$key]
    Write-Output ("  {0,-27} : {1}" -f $key, $value)
}

if ($Intrinsic)
{
    #
    #Create an array of key names
    #
    $keyName = @("OSVersion", "OSName", "ProcessorArchitecture",
     "IntegrationServicesVersion", "FullyQualifiedDomainName", "NetworkAddressIPv4",
      "NetworkAddressIPv6")
    $testPassed = $True
    foreach ($key in $keyName)
    {
        if (-not $dict.ContainsKey($key))
        {
            "Error: The key '${key}' does not exist"
            $testPassed = $False
            break
        }
    }
}
else #Non-Intrinsic
{
	if ($dict.length -gt 0)
	{
		"Info: $($dict.length) non-intrinsic KVP items found"
		$testPassed = $True
	}
	else
	{
		"Error: No non-intrinsic KVP items found"
		$testPassed = $False
	}
}

return $testPassed
