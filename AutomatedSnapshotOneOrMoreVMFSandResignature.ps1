#
#This script connects to a FlashArray and a vCenter and uses a log location. It then uses values input for VMFS volumes.  It then creates a snapshot of all of those VMFS volumes and then connects it to a VMware cluster and then rescans the hosts.
#It will then resignature the volume(s).  You must input all of the values prior to running.  #Variables is line 35, and the actual variables follow. 
#Credit goes to Cody Hostermann who made the original version of this script.  Chris Lewis and Eli Warren have edited down to an automated process.  It is ugly but it works.
#
# Requires:
# -Pure Storage PowerShell SDK 1.8+
# -VMware PowerCLI 6.3+
# -Microsoft PowerShell 5+ is highly recommend, but can be used with older versions (3+)
# -FlashArray Purity 4.7+
# -vCenter 5.5+
# >
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Warning "This script has not been run as an administrator."
    Write-Warning "Please re-run this script as an administrator!"
    write-host "Terminating Script" -BackgroundColor Red
    return
}
#Variables

#flash Array Varibles
$flasharray = 'arrayname.domain.com'
$ArrayUsername = 'pureuser'
$ArrayPassword = 'password'
$hostgroup = 'Host_group_Name'                                      # host group from pure
$snapshotNameSuffix = 'Suffix_Name'                             # suffix for the snapshot
$volumeName = 'volumeName'                              # Volume that will have snapshots

#vCenter Varibles
$vcenter = 'vcenter.domain.com'
$Username = 'domain\user'
$Password = 'password'
$clusterName = 'cluster'                                       # this is the VMWARE cluster name
$selectedVolumes = @('Volume01','Volume02')         # this is the source Datastore name

#VM Variables
$SourceVMs = @('source_vm')                                   # Source machine (Prod VM) that will be the source of the data.
$SourceVMDKs = @('soruce_vm_1.vmdk', 'source_vm_2.vmdk')
$TargetVMs = @('targetvm')                                   # Machines that will be getting the SQL DB Mounted, add extra servers with a comma.


#Create log folder if needed
$logfolder = (get-location).path +'\Logs'
if (!(test-path -path $logfolder))
{
    New-item $logfolder -type directory
}
$logfile = $logfolder + '\' + (Get-Date -Format o |ForEach-Object {$_ -Replace ':', '.'}) + "snapshotresults.txt"
write-host "Script result log can be found at $logfile" -ForegroundColor Green

#Import Modules
Import-Module VMware.VimAutomation.Core
Import-Module PureStoragePowerShellSDK

if ((!(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue)) -and (!(get-Module -Name VMware.PowerCLI -ListAvailable))) {
    if (Test-Path “C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1”)
    {
      . “C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1” |out-null
    }
    elseif (Test-Path “C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1”)
    {
        . “C:\Program Files (x86)\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1” |out-null
    }
    elseif (!(get-Module -Name VMware.PowerCLI -ListAvailable))
    {
        if (get-Module -name PowerShellGet -ListAvailable)
        {
            try
            {
                Get-PackageProvider -name NuGet -ListAvailable -ErrorAction stop
            }
            catch
            {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -Confirm:$false
            }
            Install-Module -Name VMware.PowerCLI –Scope CurrentUser -Confirm:$false -Force
        }
        else
        {
            write-host ("PowerCLI could not automatically be installed because PowerShellGet is not present. Please install PowerShellGet or PowerCLI") -BackgroundColor Red
            write-host "PowerShellGet can be found here https://www.microsoft.com/en-us/download/details.aspx?id=51451 or is included with PowerShell version 5"
            write-host "Terminating Script" -BackgroundColor Red
            return
        }
    }
    if ((!(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue)) -and (!(get-Module -Name VMware.PowerCLI -ListAvailable)))
    {
        write-host ("PowerCLI not found. Please verify installation and retry.") -BackgroundColor Red
        write-host "Terminating Script" -BackgroundColor Red
        return
    }
}
set-powercliconfiguration -invalidcertificateaction "ignore" -confirm:$false |out-null
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false  -confirm:$false|out-null

if (!(Get-Module -Name PureStoragePowerShellSDK -ErrorAction SilentlyContinue)) {
    if ( !(Get-Module -ListAvailable -Name PureStoragePowerShellSDK -ErrorAction SilentlyContinue) )
    {
        if (get-Module -name PowerShellGet -ListAvailable)
        {
            try
            {
                Get-PackageProvider -name NuGet -ListAvailable -ErrorAction stop |Out-Null
            }
            catch
            {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -Confirm:$false |Out-Null
            }
            try
            {
                Install-Module -Name PureStoragePowerShellSDK –Scope CurrentUser -Confirm:$false -Force
            }
            catch
            {
                write-host "Pure Storage PowerShell SDK cannot be installed. Please refer to the log file for details."
                add-content $logfile "Pure Storage PowerShell SDK cannot be installed."
                add-content $logfile $error[0]
                get-date -uformat %T | add-content $logfile
            }
        }
        else
        {
            write-host ("Pure Storage PowerShell SDK could not automatically be installed because PowerShellGet is not present. Please manually install PowerShellGet or the Pure Storage PowerShell SDK") -BackgroundColor Red
            write-host "PowerShellGet can be found here https://www.microsoft.com/en-us/download/details.aspx?id=51451 or is included with PowerShell version 5"
            write-host "Pure Storage PowerShell SDK can be found here https://github.com/PureStorage-Connect/PowerShellSDK"
            add-content $logfile ("FlashArray PowerShell SDK not found. Please verify installation and retry.")
            add-content $logfile "Get it here: https://github.com/PureStorage-Connect/PowerShellSDK"
            add-content $logfile "Terminating Script" 
            get-date -uformat %T | add-content $logfile
            write-host "Terminating Script" -BackgroundColor Red
            return
        }
    }
    if (!(Get-Module -Name PureStoragePowerShellSDK -ListAvailable -ErrorAction SilentlyContinue))
    {
        write-host ("Pure Storage PowerShell SDK not found. Please verify installation and retry.") -BackgroundColor Red
        write-host "Pure Storage PowerShell SDK can be found here https://github.com/PureStorage-Connect/PowerShellSDK"
        add-content $logfile ("FlashArray PowerShell SDK not found. Please verify installation and retry.")
        add-content $logfile "Get it here: https://github.com/PureStorage-Connect/PowerShellSDK"
        add-content $logfile "Terminating Script" 
        get-date -uformat %T | add-content $logfile
        write-host "Terminating Script" -BackgroundColor Red
        return
    }
}
function disconnectServers{
    disconnect-viserver -Server $vcenter -confirm:$false
    Disconnect-PfaArray -Array $endpoint 
    add-content $logfile "Disconnected vCenter and FlashArray"
    get-date -uformat %T | add-content $logfile
}
function cleanUp{
    add-content $logfile "Deleting any successfully created snapshots and volumes"
    get-date -uformat %T | add-content $logfile
    foreach ($snapshot in $snapshots)
    {
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $snapshot.name -ErrorAction SilentlyContinue |Out-Null
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $snapshot.name -Eradicate -ErrorAction SilentlyContinue |Out-Null
        add-content $logfile "Destroyed and eradicated snapshot $($snapshot.name)"
        get-date -uformat %T | add-content $logfile
    }
    foreach ($hgroupConnection in $hgroupConnections)
    {
        Remove-PfaHostGroupVolumeConnection -Array $EndPoint -VolumeName $hgroupConnection.vol -HostGroupName $hostgroup -ErrorAction SilentlyContinue |Out-Null
        add-content $logfile "Disconnected volume $($hgroupConnection.vol) from host group $($hostgroup)"
        get-date -uformat %T | add-content $logfile
    }
    foreach ($newVol in $newVols)
    {
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $newVol.name -ErrorAction SilentlyContinue |Out-Null
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $newVol.name -Eradicate -ErrorAction SilentlyContinue |Out-Null
        add-content $logfile "Destroyed and eradicated volume $($newVol.name)"
        get-date -uformat %T | add-content $logfile
    }
    $hosts = $cluster |Get-VMHost
    foreach ($esxi in $hosts) 
    {
            $argList = @($vcenter, $Creds, $esxi)
            $job = Start-Job -ScriptBlock{ 
                Connect-VIServer -Server $args[0] -Credential $args[1]
                Get-VMHost -Name $args[2] | Get-VMHostStorage -RescanAllHba -RescanVMFS
                Disconnect-VIServer -Confirm:$false
            } -ArgumentList $argList
    }
    Get-Job | Wait-Job -Timeout 120|out-null
    return
}
write-host ""
try
{
    add-content $logfile "Connecting with username $ArrayUsername"
    get-date -uformat %T | add-content $logfile
    $EndPoint = New-PfaArray -EndPoint $flasharray -UserName $ArrayUsername -Password (ConvertTo-SecureString -AsPlainText $ArrayPassword -Force) -IgnoreCertificateError -ErrorAction stop
}
catch
{
    add-content $logfile ""
    add-content $logfile "Connection to FlashArray $($flasharray) failed."
    add-content $logfile $Error[0]
    add-content $logfile "Terminating Script"
    get-date -uformat %T | add-content $logfile  
    write-host "Connection to FlashArray $($flasharray) failed. Please check log for details"
    write-host "Terminating Script" -BackgroundColor Red
    return
}
get-date -uformat %T | add-content $logfile
add-content $logfile 'Connected to the following FlashArray:'
add-content $logfile $flasharray
add-content $logfile '----------------------------------------------------------------------------------------------------'
$options = [System.Management.Automation.Host.ChoiceDescription[]] @("&Yes", "&No", "&Quit")
try
{
    get-date -uformat %T | add-content $logfile
    add-content $logfile "Connecting with username $Username"
    connect-viserver -Server $vcenter  -Protocol https -User $Username -Password $Password -ErrorAction Stop |out-null
    add-content $logfile "Connected to the following vCenter: $vcenter"
    add-content $logfile '----------------------------------------------------------------------------------------------------'
}
catch
{
    write-host "Failed to connect to vCenter. Refer to log for details." -BackgroundColor Red
    write-host "Terminating Script" -BackgroundColor Red
    add-content $logfile "Failed to connect to vCenter"
    add-content $logfile $vcenter
    add-content $logfile $Error[0]
    add-content $logfile "Terminating Script"
    get-date -uformat %T | add-content $logfile
    Disconnect-PfaArray -Array $EndPoint
    return
}

#setup credentials for Powershell Session
$pword = ConvertTo-SecureString -String $Password -AsPlainText -Force
$Credential = New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList $Username, $PWord

#stop SQL DB
foreach ($vm in $targetVMs)
{
    try 
    {
       
        $fullPath = $(Get-Location).Path + '\offline-database.ps1'
        $TargetVMSession = New-PSSession -ComputerName $vm -Credential $Credential
        add-content $logfile "Offline Database"
        get-date -uformat %T | add-content $logfile
        Invoke-Command -Session $TargetVMSession -FilePath $fullPath | Out-Null
        start-sleep -s 15
        #Exit-PSSession
        Remove-PSSession -session $TargetVMSession
    }
    catch 
    {
        add-content $logfile "Terminating Script. Could not offline database on $vm."  
        get-date -uformat %T | add-content $logfile
        #write-host "Terminating Script. Could not stop SQL database on $vm. Refer to the log for details." -BackgroundColor Red
        add-content $logfile $error[0]
        #disconnectServers
        #return
    }
}

add-content $logfile '----------------------------------------------------------------------------------------------------'
#disconnect disk from Windows instance
foreach ($vm in $targetVMs)
{
    try 
    {
        add-content $logfile "Setting drives on $vm offline"
        get-date -uformat %T | add-content $logfile
        $fullPath = $(Get-Location).Path + '\offline-disks.ps1'
        $TargetVMSession = New-PSSession -ComputerName $vm -Credential $Credential
        Invoke-Command -session $targetVMSession -FilePath $fullPath -AsJob | Out-Null
        Start-Sleep -s 15
        #Exit-PSSession 
        Remove-PSSession -session $TargetVMSession            
    }
    catch
    {
        add-content $logfile $error[0]
    }    
}
add-content $logfile '----------------------------------------------------------------------------------------------------'
#disconnect VMDK from VM
foreach ($vm in $targetVMs)
{
    try 
    {
        Add-Content $logfile "Removing VMDK from $vm"
        get-date -uformat %T | add-content $logfile
        foreach ($vol in $selectedVolumes)
        {
            Add-content $logfile "removing disks from $vm on $vol"
            get-date -uformat %T | add-content $logfile
            Get-VM $vm | get-harddisk | where-object {$_.filename -like "*$vol*"} | remove-harddisk -confirm:$false
            start-sleep -Seconds 15
        }
    }
    catch
    {
        add-content $logfile "Error in Removing $vmdk to $vm"
        get-date -uformat %T | add-content $logfile
        add-content $logfile $error[0]
        write-host "Error Removing VMDK. See log for details." -BackgroundColor Red
    }
} 
 
add-content $logfile '----------------------------------------------------------------------------------------------------'
add-content $logfile 'remove datastore from vCenter'
get-date -uformat %T | add-content $logfile
#remove Datastore from vCenter
foreach ($vm in $targetVMs)
{
    try 
    {
        $hostname = get-vm $vm | get-vmhost
        foreach($selectedvolume in $selectedVolumes)
        {
            $datastores = get-vmhost $hostname | get-datastore | where-object {$_.name -like "snap*$selectedVolume*"}
            Foreach ($datastore in $datastores) 
            {
                foreach ($hostname in $(get-vmhost $hostname | get-cluster | get-vmhost))
                {
                    $hostview = Get-View $hostname
                    $StorageSys = Get-View $HostView.ConfigManager.StorageSystem
                    add-content $logfile "Unmounting VMFS Datastore $($datastore.extensiondata.Name) from host $($hostview.Name)"
                    get-date -uformat %T | add-content $logfile
                    #unmount storage
                    $StorageSys.UnmountVmfsVolume($datastore.ExtensionData.Info.vmfs.uuid)
                }
            }
            Foreach ($datastore in $datastores) 
            {
                add-content $logfile "Removing Datastore $datastore from host $hostname"
                get-date -uformat %T | add-content $logfile
                #remove Datastore
                remove-datastore -vmhost $hostname -datastore $datastore -confirm:$false 
            }
        }
    }
    catch 
    {
        add-content $logfile "Terminating Script. Could not remove data store $datastore from $hostname.  This maybe expected if anticpated snap-999999-$selectedVolume datastore was not present on vCenter initially" 
        get-date -uformat %T | add-content $logfile 
        write-host "Could not remove data store $datastore from $hostname. Refer to the log for details." -BackgroundColor Red
        add-content $logfile $error[0]
    }
}

add-content $logfile '----------------------------------------------------------------------------------------------------'
#remove old snapshots
$snapshots = Get-PfaVolumeSnapshots -Array $Endpoint -VolumeName $volumeName
foreach ($oldsnapshot in $snapshots)
{
    try 
    {   add-content $logfile "searching for old snapshots and will remove them if they exist"
        get-date -uformat %T | add-content $logfile
        if ($oldsnapshot.name -like "*$snapshotNameSuffix*")
        {
            Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $oldsnapshot.name -ErrorAction SilentlyContinue |Out-Null
            Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $oldsnapshot.name -Eradicate -ErrorAction SilentlyContinue |Out-Null
            add-content $logfile "Destroyed and eradicated previously existing snapshot $($snapshot.name)"
            get-date -uformat %T | add-content $logfile
        }
    }
    Catch
    {
        add-content $logfile "Terminating Script. Could not remove snapshot from $endpoint." 
        get-date -uformat %T | add-content $logfile 
        write-host "Terminating Script. Could not remove snapshot from $endpoint. Refer to the log for details." -BackgroundColor Red
        add-content $logfile $error[0]
    }
}
#remove volumes from Array
add-content $logfile '----------------------------------------------------------------------------------------------------'
$oldVolumes = Get-PfaVolumes -Array $Endpoint | Where-Object {$_.name -like "$volumeName-AutoCopy*"}
$hostGroupVols = get-pfahostgroupvolumeconnections -array $endpoint -HostGroupName $hostgroup | where-object {$_.vol -like "$volumeName-AutoCopy*"}
add-content $logfile "searching for old volumes and will remove them if they exist"
get-date -uformat %T | add-content $logfile
foreach ($oldVolume in $oldVolumes)
{
    add-content $logfile "found $($oldVolume.name)"
    get-date -uformat %T | add-content $logfile
    foreach ($hostgroupVol in $hostGroupVols)
    {
        try 
        {
            Remove-PfaHostGroupVolumeConnection -Array $endpoint -VolumeName $($oldVolume.name) -HostGroupName $hostgroup | Out-Null
            Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $($oldVolume.name) | Out-Null
            Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $($oldVolume.name) -Eradicate | Out-Null
            add-content $logfile "Destroyed and eradicated previously existing volume $($oldVolume.name)"
            get-date -uformat %T | add-content $logfile
        }
        Catch
        {
            add-content $logfile "Terminating Script. Could not remove old volume $oldVolume from $endpoint."  
            get-date -uformat %T | add-content $logfile
            write-host "Terminating Script. Could not remove volume from $endpoint. Refer to the log for details." -BackgroundColor Red
            add-content $logfile $error[0]
        }
    }
}
add-content $logfile "Selected volumes are: "
foreach($selectedVolume in $selectedVolumes)
{
    add-content $logfile $selectedVolume
}
get-date -uformat %T | add-content $logfile

#find FlashArray volumes that host VMFS datastores
$selectedFAVolumes = @()
$FAVols = Get-PfaVolumes -Array $EndPoint
foreach ($selectedVolume in $selectedVolumes)
{
    $vmfs = get-datastore -name $selectedVolume
    $lun = $vmfs.ExtensionData.Info.Vmfs.Extent.DiskName 
    $volserial = ($lun.ToUpper()).substring(12)
    $purevol = $FAVols | where-object { $_.serial -eq $volserial }
    $selectedFAVolumes += $purevol.name
}
add-content $logfile '----------------------------------------------------------------------------------------------------'
add-content $logfile "Selected cluster is $($clusterName)"
get-date -uformat %T | add-content $logfile
try
{
    $cluster = get-cluster $clusterName
}
catch
{
    add-content $logfile "Terminating Script. Could not find entered cluster."
    get-date -uformat %T | add-content $logfile  
    write-host "Could not find entered cluster. Terminating Script. Refer to the log for details." -BackgroundColor Red
    add-content $logfile $error[0]
    disconnectServers
    return
}

#identify host group for volume connection. Looks for the first FlashArray host that matches an ESXi by iSCSI initiators or FC and then finds its host group. If not in a host group the process fails.
try
    {
        $fcinitiators = @()
        $iscsiinitiators = @()
        $iscsiadapters = $cluster  |Get-VMHost | Get-VMHostHBA -Type iscsi | Where-Object {$_.Model -eq "iSCSI Software Adapter"}
        $fcadapters = $cluster  |Get-VMHost | Get-VMHostHBA -Type FibreChannel | Select-Object VMHost,Device,@{N="WWN";E={"{0:X}" -f $_.PortWorldWideName}} | Format-table -Property WWN -HideTableHeaders |out-string
        foreach ($iscsiadapter in $iscsiadapters)
        {
            $iqn = $iscsiadapter.ExtensionData.IScsiName
            $iscsiinitiators += $iqn.ToLower()
        }
        $fcadapters = (($fcadapters.Replace("`n","")).Replace("`r","")).Replace(" ","")
        $fcadapters = &{for ($i = 0;$i -lt $fcadapters.length;$i += 16)
        {
                $fcadapters.substring($i,16)
        }}
        foreach ($fcadapter in $fcadapters)
        {
            $fcinitiators += $fcadapter.ToLower()
        }
        if ($iscsiinitiators.count -gt 0)
        {
            add-content $logfile '----------------------------------------------------------------------------------------------------'
            add-content $logfile "Found the following iSCSI initiators in the cluster:"
            add-content $logfile $iscsiinitiators
            get-date -uformat %T | add-content $logfile
        }
        if ($fcinitiators.count -gt 0)
        {
            add-content $logfile '----------------------------------------------------------------------------------------------------'
            add-content $logfile "Found the following Fibre Channel initiators in the cluster:"
            add-content $logfile $fcinitiators
            get-date -uformat %T | add-content $logfile
        }
        $fahosts = Get-PfaHosts -array $endpoint
        $script:hostgroup = $null
        foreach ($fahost in $fahosts)
        {
            foreach ($iscsiinitiator in $iscsiinitiators)
            {
                if ($fahost.iqn -contains $iscsiinitiator)
                {
                    add-content $logfile "Found a matching host called $($fahost.name)"
                    get-date -uformat %T | add-content $logfile
                    if ($fahost.hgroup -eq $null)
                    {
                        throw "The identified host is not in a host group. Terminating script"
                    }
                    $script:hostgroup = $fahost.hgroup
                    break
                }
            }
            if ($hostgroup -ne $null)
            {
                break
            }
            foreach ($fcinitiator in $fcinitiators)
            {
                if ($fahost.wwn -contains $fcinitiator)
                {
                    add-content $logfile "Found a matching host called $($fahost.name)"
                    get-date -uformat %T | add-content $logfile
                    if ($fahost.hgroup -eq $null)
                    {
                        throw "The identified host is not in a host group. Terminating script"
                    }
                    $script:hostgroup = $fahost.hgroup
                    break
                }
            }
            if ($hostgroup -ne $null)
            {
                break
            }
        }
        if ($hostgroup -eq $null)
        {
              throw "No matching host group could be found"
        }
        else
        {
            add-content $logfile '----------------------------------------------------------------------------------------------------'
            add-content $logfile "The host group identified is named $($hostgroup)"
            get-date -uformat %T | add-content $logfile
        }
    }
catch
{
        write-host "No matching host group could be found. See log for details." -BackgroundColor Red
        add-content $logfile $Error[0]
        disconnectServers
        return
}
add-content $logfile '----------------------------------------------------------------------------------------------------'
#start snapshot process
try
{
    if ($snapshotNameSuffix -ne "")
    {
        add-content $logfile "Snapshot suffix will be $($snapshotNameSuffix)"
        get-date -uformat %T | add-content $logfile
        $snapshots = New-PfaVolumeSnapshots -Array $endpoint -Sources $purevol.name -Suffix $snapshotNameSuffix
    }
    else
    {
       $snapshots = New-PfaVolumeSnapshots -Array $endpoint -Sources $purevol.name
    }
}
catch
{
    add-content $logfile "Deleting any successfully created snapshots"
    foreach ($snapshot in $snapshots)
    {
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $snapshot.name -ErrorAction SilentlyContinue |Out-Null
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $snapshot.name -Eradicate -ErrorAction SilentlyContinue |Out-Null
        add-content $logfile "Destroyed and eradicated snapshot $($snapshot.name)"
        get-date -uformat %T | add-content $logfile
    }
    add-content $logfile "Terminating Script. Could not create snapshots."  
    get-date -uformat %T | add-content $logfile
    write-host "Terminating Script. Could not create snapshots. Refer to the log for details." -BackgroundColor Red
    add-content $logfile $error[0]
    disconnectServers
    return
}
add-content $logfile "Created $($snapshots.count) snapshot(s):"
add-content $logfile $snapshots.name
get-date -uformat %T | add-content $logfile

#create volumes from snapshots
add-content $logfile '----------------------------------------------------------------------------------------------------'
add-content $logfile "Creating $($snapshots.count) volume(s)..."
get-date -uformat %T | add-content $logfile
try
{
    $newVols = @()
    $randomNum = Get-Random -Maximum 99999 -Minimum 10000
    #create new vol from snapshot add a suffix to original name of -AutoCopy-<random 5 digit number>
    foreach ($snapshot in $snapshots)
    {
        $newVols += New-PfaVolume -Source $snapshot.name -VolumeName ("$($snapshot.source)-AutoCopy-$($randomNum)") -Array $EndPoint
        add-content $logfile "Created volume named $($snapshot.source)-AutoCopy-$($randomNum)"
        get-date -uformat %T | add-content $logfile
    }
}
catch
{
    add-content $logfile "Failed to create new volumes."
    add-content $logfile $error[0]
    add-content $logfile "Deleting any successfully created snapshots and volumes"
    get-date -uformat %T | add-content $logfile
    foreach ($snapshot in $snapshots)
    {
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $snapshot.name -ErrorAction SilentlyContinue |Out-Null
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $snapshot.name -Eradicate -ErrorAction SilentlyContinue |Out-Null
        add-content $logfile "Destroyed and eradicated snapshot $($snapshot.name)"
        get-date -uformat %T | add-content $logfile
    }
    foreach ($newVol in $newVols)
    {
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $newVol.name -ErrorAction SilentlyContinue |Out-Null
        Remove-PfaVolumeOrSnapshot -Array $EndPoint -Name $newVol.name -Eradicate -ErrorAction SilentlyContinue |Out-Null
        add-content $logfile "Destroyed and eradicated volume $($newVol.name)"
        get-date -uformat %T | add-content $logfile
    }
    add-content $logfile "Terminating Script."
    get-date -uformat %T | add-content $logfile  
    write-host "Terminating Script. Could not create volume(s). Refer to the log for details." -BackgroundColor Red
    disconnectServers
    return
}
#connecting to host group
add-content $logfile '----------------------------------------------------------------------------------------------------'
try
{
    $hgroupConnections = @()
    add-content $logfile "Connecting volumes to host group"
    get-date -uformat %T | add-content $logfile
    foreach ($newVol in $newVols)
    {
        $hgroupConnections += New-PfaHostGroupVolumeConnection -Array $EndPoint -VolumeName $newVol.name -HostGroupName $hostgroup
        add-content $logfile "Connected $($newVol.name) to host group $($hostgroup)"
        get-date -uformat %T | add-content $logfile
    }
}
catch
{
    add-content $logfile "Failed to connect new volumes."
    add-content $logfile $error[0]
    cleanUp
    add-content $logfile "Terminating Script."  
    get-date -uformat %T | add-content $logfile
    write-host "Terminating Script. Could not create volume(s). Refer to the log for details." -BackgroundColor Red
    disconnectServers
    return
}
add-content $logfile '----------------------------------------------------------------------------------------------------'

$hosts = get-cluster $cluster |Get-VMHost | ForEach-Object {$_.name}
foreach ($hostname in $hosts) 
{
    add-content $logfile "recscanning host $hostname" 
    get-date -uformat %T | add-content $logfile  
    get-vmhost $hostname | Get-VMHostStorage -RescanAllHba -refresh | out-null
}

add-content $logfile "HBA Rescan completed "
get-date -uformat %T | add-content $logfile

#choose a host in the cluster that is online to resignature the volumes
$resigHost = get-cluster $cluster |Get-VMHost |where-object {($_.ConnectionState -eq 'Connected')} |Select-Object -last 1

add-content $logfile '----------------------------------------------------------------------------------------------------'
#validate resignaturing process
try
{
    $esxcli = get-esxcli -VMHost $resigHost -v2
    foreach ($SelectedVolume in $selectedVolumes)
    {
        $unresolvedvmfs = $esxcli.storage.vmfs.snapshot.list.invoke() | where-object {$selectedVolume -contains $_.VolumeName}
        add-content $logfile "found unsignatured disks $($unresolvedvmfs.Volumename) on Host $resigHost"
        if (($unresolvedVMFS.canresignature|select-object -unique).count -ne 1)
        {
            foreach ($unresolved in $unresolvedVMFS)
            {
                if ($unresolved.canresignature -eq $false)
                {
                    add-content $logfile "ERROR: Volume $($unresolved.volumeName) is cannot be resolved for the following reason:"
                    add-content $logfile $unresolved.Reasonfornonresignaturability
                    get-date -uformat %T | add-content $logfile
                }
            }
            throw "Cannot resignature one or more volumes. Terminating script. See log for details."
        }
    }

    
    if ($unresolvedvmfs.count -eq 0)
    {
        throw "Expected volumes to be resignatured were not found. Terminating script."
    }
}
catch
{
    write-host $error[0] -BackgroundColor Red
    add-content $logfile $error[0]
    cleanUp
    disconnectServers
    return
}
add-content $logfile '----------------------------------------------------------------------------------------------------'
#resignature volumes
try
{
    add-content $logfile "Resignaturing the VMFS volume(s) ..."
    foreach ($unresolved in $unresolvedvmfs)
    {
        $resigArgs = $esxcli.storage.vmfs.snapshot.resignature.CreateArgs()
        $resigArgs.volumelabel = $unresolved.volumename
        $resigArgs = $esxcli.storage.vmfs.snapshot.resignature.Invoke($resigArgs)
        add-content $logfile "Resignatured the VMFS volume $($unresolved.volumename)."
        get-date -uformat %T | add-content $logfile
    }
}
catch
{
    add-content $logfile "Error resignaturing volumes."
    get-date -uformat %T | add-content $logfile
    add-content $logfile $error[0]
    write-host "Error resignaturing volumes. See log for details." -BackgroundColor Red
    cleanUp
}
add-content $logfile '--------------------------------------------------------------------------------------------------'

#make sure all hosts have visability to the resignatured Datastore
$hosts = get-cluster $cluster |Get-VMHost | ForEach-Object {$_.name}
foreach ($hostname in $hosts) 
{
    add-content $logfile "recscanning vmfs on host $hostname" 
    get-date -uformat %T | add-content $logfile  
    get-vmhost $hostname | Get-VMHostStorage -RescanVMFS -refresh | out-null
}

add-content $logfile "VMFS Rescan completed "
get-date -uformat %T | add-content $logfile

#present VMDK to VM 
foreach ($targetVM in $targetVMs)
{
    try 
    {   
        foreach($selectedVolume in $selectedVolumes)
        {
            Add-Content $logfile "Presenting VMDK to $targetvm"
            $datacenter = get-vm $targetVM |get-vmhost | get-datacenter | ForEach-Object {$_.name}
            $datastore = Get-vm $targetVM | get-vmhost | get-datastore | Where-Object {$_.name -like "snap*$selectedVolume"} | ForEach-Object {$_.name}
            Add-Content $logfile "Target VM host in the data center $datacenter sees the $datastore datastore"
            ForEach ($sourceVM in $sourceVMs)
            {
                foreach ($SourceVMDK in $sourceVMDKs)
                {
                    $vmdkpaths = Get-ChildItem -recurse -path "VMstore:\$datacenter\$datastore\" -include * | Where-Object {$_.name -like "$sourceVMDK"} | ForEach-Object {$_.datastorefullpath}
                    Add-content $logfile "Path to $sourceVMDK vmdk file $vmdkpaths found."
                    foreach ($vmdkpath in $vmdkpaths)
                    {
                        if ($vmdkpath -notlike "*-flat.vmdk" -and $vmdkpath -notlike "*-ctk.vmdk") 
                        {
                            get-vm $TargetVM | new-harddisk -diskpath $vmdkpath | out-null
                            Add-Content $logfile "Presented $vmdkpath to $targetvm"
                            get-date -uformat %T | add-content $logfile
                        }
                    }
                }
            }
        }
    }
    catch
    {
        add-content $logfile "Error in Presenting Source vmdk to $targetVM"
        get-date -uformat %T | add-content $logfile
        add-content $logfile $error[0]
        write-host "Error presenting VMDK. See log for details." -BackgroundColor Red
    }
}   
add-content $logfile '----------------------------------------------------------------------------------------------------'
#Present Disks to windows
foreach ($vm in $targetVMs)
{
    try 
    {
        Add-Content $logfile "Adding Disk to Windows"
        get-date -uformat %T | add-content $logfile
        $fullPath = (Get-Location).Path + '\online-disks.ps1'
        $TargetVMSession = New-PSSession -ComputerName $vm -Credential $Credential
        Invoke-Command -session $TargetVMSession -FilePath $fullPath -AsJob | Out-Null
        start-sleep -s 15
        #Exit-PSSession
        Remove-PSSession -session $TargetVMSession
    }    
    catch 
    {
        add-content $logfile $error[0]
    }
} 
add-content $logfile '----------------------------------------------------------------------------------------------------'
add-content $logfile "starting SQL"

foreach ($vm in $targetVMs)
{
    try 
    {
        Add-Content $logfile "Online Database"
        get-date -uformat %T | add-content $logfile
        $fullPath = (Get-Location).Path + '\online-database.ps1'
        $TargetVMSession = New-PSSession -ComputerName $vm -Credential $Credential
        Invoke-Command -session $TargetVMSession -FilePath $fullPath | Out-Null
        start-sleep -s 15
        #Exit-PSSession
        Remove-PSSession -session $TargetVMSession
    }
    catch 
    {
        add-content $logfile "Terminating Script. Could not online database on $vm."  
        #write-host "Terminating Script. Could not start SQL Server on $vm. Refer to the log for details." -BackgroundColor Red
        add-content $logfile $error[0]
        #disconnectServers
        #return
    }
}

disconnectServers
add-content $logfile "Process completed successfully!"
get-date -uformat %T | add-content $logfile
write-host "Process completed successfully!" -ForegroundColor Green