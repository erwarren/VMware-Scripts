README.txt
High Level Purpose:  quickly and efficiently refresh data from one VM to another by leveraging PowerShell, VMware PowerCLI, and pure storage PowerShell API.

Technical process:
1) Offline chosen DB
2) Offline disks from chosen Windows based VM
3) Remove VMDK files from VM
4) Unmount data store from cluster
5) Remove data store from cluster
6) Clean up any old snapshots on the chosen Pure Array
7) Clean up any old volumes on the chosen Pure Array
8) Take a new snapshot on the chosen Pure Array
9) Convert the new snapshot to a volume on the chosen Pure Array
10) Present the new volume to the selected host group
11) Rescan HBA’s for new volume
12) Re-signature new volume to retain consistent data
13) Represent VMFS Volume to selected cluster
14) Reconnect VMDKs to VM
15) Online disks and verify they’re lettered correctly and in a read/write state
16) Online selected database

Technical Setup:
1) In the Offline-Database.ps1 script, input the database name in single quotes at the $database variable.
2) In the Offline-disks.ps1 script, input the drive letters that will be taken offline in the $driveLetter variable in single quotes separated by a coma in the parenthesis.  This array will be used to take the disks offline when needed.
3) In the Online-disks.ps1 script, there are 2 variable arrays that need to be built.
First, Input the drive labels that will be incoming from the source Windows instance in the $labels variable in single quotes separated by a coma in the parenthesis.  
Second, input the drive letters that will be taken online in the $driveLetter variable in single quotes separated by a coma in the parenthesis.  This array will be used to take the disks online when needed.
These will need to be input in the same order to allow the volumes to be lettered correctly for SQL, to restart correctly
4) In the Online-Database.ps1 script, input the database name in single quotes at the $database variable.
5) In the SnapshotOneOrMoreVMFSandResignature.ps1 script, there are a number of variable values that will need to be populated.  All of these variables are located between lines 21 and 41 of the script.
#flash Array Variables
$flasharray = 'FQDN_of_Array'
$ArrayUsername = 'Pure_Storage_User'
$ArrayPassword = 'Pure_Storage_Password'
$hostgroup = 'Array_Based_Host_Group'                  	
$snapshotNameSuffix = 'Unique_Snapshot_Suffix'         	
$volumeName = 'Array_Volume_Source_With_Snapshots'

#vCenter Variables
$vcenter = 'FQDN_of_vCenter'
$Username = 'Domain\User_Name'
$Password = 'password'
$clusterName = 'vCenter_Cluster_Name'
$selectedVolumes = @('Datastore_Name') 

#VM Variables
$SourceVMs = @('Source_VM_Name')
 $SourceVMDKs = @('Source_VMDK_1.vmdk', 'Source_VMDK_2.vmdk')	
$TargetVMs = @('Target_VM_Name')

