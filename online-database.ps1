$DatabaseName = 'DB_Name'

Import-Module SQLPS

$iname = [System.Data.Sql.SqlDataSourceEnumerator]::Instance.GetDataSources()|?{$_.ServerName -eq $env:COMPUTERNAME} | foreach-object {$_.InstanceName}

$dbpath = "$env:COMPUTERNAME" +'\'+ "$iname"

Invoke-Sqlcmd -ServerInstance $dbpath -Database master -Query "ALTER DATABASE $DatabaseName SET ONLINE WITH ROLLBACK IMMEDIATE"

Exit