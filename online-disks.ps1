$labels = @('Drive_Label_1', 'Drive_Label_2')
$driveLetters = @('DL1','DL2')


$s = get-disk | where-object { $_.OperationalStatus -like 'Offline' } | ForEach-Object { $_.Number }
foreach ($r in $s)
{
    "Select disk $r", "online disk" | diskpart.exe
    "exit" | diskpart.exe
    set-disk -number $r -IsReadOnly $false
}
$i=0
foreach ($label in $labels)
{
    $vol = get-volume | Where-Object {$_.FileSystemLabel -like $Label}
    if ($vol -like $label[$i])
    {
        set-volume -DriveLetter $driveLetters[$i]
        i++ 
    }
}
