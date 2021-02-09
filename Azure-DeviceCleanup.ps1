<#PSScriptInfo

.VERSION 1.0

.AUTHOR Andrew Blackburn 
(Some pieces/inspiration taken from:
-Michael Niehaus' Get-WindowsAutoPilotInfo.ps1 - https://oofhours.com/2020/07/13/automating-the-windows-autopilot-device-hash-import-and-profile-assignment-process/
-Oliver Kieselbach's Start-AutopilotCleanupCSV.ps1 - https://oliverkieselbach.com/2020/01/21/cleanup-windows-autopilot-registrations/)

.RELEASENOTES
Version 1.0:  Initial version.
#>

<#
.SYNOPSIS
Cleans up a device in Azure in the following order:
1. Intune
2. Autopilot
3. AAD

.DESCRIPTION
This script assists with the decommissioning of a device in your Azure tenant.

.PARAMETER DeviceSerial
The serial number of the computer you would like to decommission in your Azure tenant.  

.EXAMPLE
.\Azure-DeviceCleanup.ps1 -DeviceSerial 1234567890
#>

[CmdletBinding(DefaultParameterSetName = 'Default')]
param(
	[Parameter(Mandatory=$False)] [String] $DeviceSerial = ""
)

$CleanupConfirm = Read-Host "Cleanup device with serial number $DeviceSerial in Intune, Autopilot, and then AAD? (y/n)"
if ($CleanupConfirm -eq 'y') {
# Get NuGet
$provider = Get-PackageProvider NuGet -ErrorAction Ignore
if (-not $provider) {
    Write-Host "Installing provider NuGet"
    Find-PackageProvider -Name NuGet -ForceBootstrap -IncludeDependencies
}

# Get WindowsAutopilotIntune module (and dependencies)
$module = Import-Module WindowsAutopilotIntune -PassThru -ErrorAction Ignore
if (-not $module) {
    Write-Host "Installing module WindowsAutopilotIntune"
    Install-Module WindowsAutopilotIntune -Force
}
Import-Module WindowsAutopilotIntune -Scope Global

# Get Azure AD if needed
$module = Import-Module AzureAD -PassThru -ErrorAction Ignore
if (-not $module)
{
    Write-Host "Installing module AzureAD"
    Install-Module AzureAD -Force
}

# Connect
$graph = Connect-MSGraph
Write-Host "Connected to Intune tenant $($graph.TenantId)"
$aadId = Connect-AzureAD -AccountId $graph.UPN
Write-Host "Connected to Azure AD tenant $($aadId.TenantId)"

# Get serial number of device this is running on
#$CimSession = New-CimSession
#$DeviceSerial = (Get-CimInstance -CimSession $CimSession -Class Win32_BIOS).SerialNumber

Write-Host "Gathering details for device..."

# Get Autopilot device details
$AutopilotDevice = Get-AutopilotDevice -serial "$DeviceSerial"
if (!($AutopilotDevice)) {
    Write-Host "Device does not exist in Autopilot yet." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    exit} else {
    Write-Host "Found Autopilot details for device: $($AutopilotDevice.id)" -ForegroundColor Blue
}

# Get AAD device details
$AADDevice = Get-AzureADDevice -Filter "deviceId eq guid'$($AutopilotDevice.azureActiveDirectoryDeviceId)'"
if (!($AADDevice)) {
    Write-Host "Device does not exist in AAD yet, exiting... This shouldn't hapen." -ForegroundColor Red
    Start-Sleep -Seconds 10
    exit 1
} else {
    Write-Host "Found AAD details for device: $($AADDevice.DeviceId)" -ForegroundColor Blue
}

# Get Intune device details
if (!($AutopilotDevice.managedDeviceId) -or ($AutopilotDevice.managedDeviceId -eq "00000000-0000-0000-0000-000000000000")) {
    Write-Host "Managed device ID not available (likely because it doesn't exist in Intune yet)" -ForegroundColor Yellow
} else {
    # Remove device from Intune
    $IntuneDevice = Get-IntuneManagedDevice -managedDeviceId $AutopilotDevice.managedDeviceId
    $IntuneDeleteConfirm = Read-Host "Delete device from Intune? (y/n)"
    if ($IntuneDeleteConfirm -eq 'y') {
        Remove-IntuneManagedDevice -managedDeviceId $IntuneDevice.id
        Write-Host "Device deleted from Intune" -ForegroundColor Green
    }
}

# Remove device from Autopilot
$AutopilotDeleteConfirm = Read-Host "Delete device from Autopilot? (y/n)"
if ($AutopilotDeleteConfirm -eq 'y') {
    Remove-AutopilotDevice -id $AutopilotDevice.id
    Invoke-AutopilotSync
    while (Get-AutopilotDevice -serial "$DeviceSerial") {
        Write-Host "Waiting to see if device was deleted..." -ForegroundColor Yellow
        Start-Sleep -Seconds 30
        } 
        Write-Host "Device deleted from Autopilot" -ForegroundColor Green
}

# Remove device from AAD
$AADDeleteConfirm = Read-Host "Delete device from AAD? (y/n)"
if ($AADDeleteConfirm -eq 'y') {
    Remove-AzureADDevice -ObjectId $AADDevice.ObjectId
    Write-Host "Device deleted from AAD" -ForegroundColor Green
    }
} else {Write-Host "User aborted script." -ForegroundColor Red}