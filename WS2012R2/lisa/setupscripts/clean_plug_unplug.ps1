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
    This setup script, that will run before the VM is booted, will Add VHDx Hard Driver to VM.


.Description
   This is a cleanup script that will run after the VM shuts down.
   This script delete the two hard drives identified in scsi= test parameters.

   Cleanup scripts are run in a separate PowerShell environment,
   so they do not have access to the environment running the ICA
   scripts.


   The .xml entry for this script could look like either of the
   following:


   <cleanupScript>SetupScripts\clean_plug_unplug.ps1</cleanupScript>


  The  scripts will always pass the vmName, hvServer, and a string of testParams from the 
  test definition separated by semicolons.

  Test params xml entry:
      <testparams>
        <param>SectorSize1=512</param>
        <param>DefaultSize1=5GB</param>
        <param>SectorSize2=512</param>
        <param>DefaultSize2=2GB</param>
     </testparams>

   
   Cleanup scripts need to parse the testParam string to find any
   parameters it needs.


   All setup and cleanup scripts must return a boolean ($true or $false)
  to indicate if the script completed successfully or not.
  
  .Parameter vmName
    Name of the VM to remove disk from .

  .Parameter hvServer
    Name of the Hyper-V server hosting the VM.

  .Parameter testParams
    Test data for this test case

  .Example
    setupScripts\clean_plug_unplug.ps1 -vmName VM_NAME -hvServer HYPERV_SERVER -testParams "SectorSize1=512;DefaultSize1=5GB;SectorSize2=512;DefaultSize2=2GB"
#>
############################################################################

param([string] $vmName, [string] $hvServer, [string] $testParams)

function RemoveVhdx([string] $vmName, [string] $hvServer,
                        [string]$sectorSize, [string] $defaultSize)
{   
    $vhdxName = $vmName + "-" + $sectorSize + "-" + $defaultSize + "-test"
    $vhdxDisks = Get-VMHardDiskDrive -VMName $vmName
    foreach ($vhdx in $vhdxDisks)
    {
        $vhdxPath = $vhdx.Path
        if ($vhdxPath.Contains($vhdxName))
        {
            "Info : Removing drive $vhdxName"
            Remove-VMHardDiskDrive -vmName $vmName -ControllerType $vhdx.controllerType -ControllerNumber $vhdx.controllerNumber -ControllerLocation $vhdx.ControllerLocation -ComputerName $hvServer
            if ($error.Count -gt 0)
            {
                "Error: Remove-VMHardDiskDrive failed to delete drive on SCSI controller "
                $error[0].Exception
                return $false
            }
            $error.Clear()
        }
    }
}
############################################################################
#
# Main entry point for script
#
############################################################################

$retVal   = $False
$sectorSize = $null

#
# Check input arguments
#
if ($vmName -eq $null -or $vmName.Length -eq 0)
{
    "Error: VM name is null"
    return $False
}
if ($hvServer -eq $null -or $hvServer.Length -eq 0)
{
    "Error: hvServer is null"
    return $False
}
if ($testParams -eq $null -or $testParams.Length -lt 3)
{
    "Error: setupScript requires test params"
    return $False
}

#
# Parse the testParams string
#
$params = $testParams.TrimEnd(";").Split(";")
foreach ($p in $params)
{
    $fields = $p.Split("=")
    $value = $fields[1].Trim()

    switch ($fields[0].Trim())
    {
      "SectorSize1"    { $sectorSize1    = $fields[1].Trim() }
      "DefaultSize1"   { $defaultSize1  = $fields[1].Trim() }
      "SectorSize2"    { $sectorSize2    = $fields[1].Trim() }
      "DefaultSize2"   { $defaultSize2  = $fields[1].Trim() }
      default     {}  # unknown param - just ignore it
    }
}

#
#Removing last vhd attached
#
RemoveVhdx $vmName $hvServer $sectorSize1 $defaultSize1
RemoveVhdx $vmName $hvServer $sectorSize2 $defaultSize2

#
# Removing the .vhdx files
#
$vmDrive = Get-VMHardDiskDrive -VMName $vmName -ComputerName $hvServer
$lastSlash = $vmDrive[0].Path.LastIndexOf("\")
$defaultVhdPath = $vmDrive[0].Path.Substring(0,$lastSlash)

if (-not $defaultVhdPath.EndsWith("\"))
{
    $defaultVhdPath += "\"
}

$defaultVhdPath1 = $defaultVhdPath +  $vmName + "-" + $sectorSize1 + "-" + $defaultSize1 + "-test.vhdx"
$defaultVhdPath2 = $defaultVhdPath +  $vmName + "-" + $sectorSize2 + "-" + $defaultSize2 + "-test.vhdx"

if((Test-Path $defaultVhdPath1) -and $defaultVhdPath1.EndsWith(".vhdx"))
{
    Remove-Item $defaultVhdPath1
}

if((Test-Path $defaultVhdPath2) -and $defaultVhdPath2.EndsWith(".vhdx"))
{
    Remove-Item $defaultVhdPath2
}


$retVal = $True
return $True