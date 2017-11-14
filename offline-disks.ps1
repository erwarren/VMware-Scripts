$driveLetters = @('DL1','DL2')

foreach ($letter in $driveLetters)
{
    $s = get-disk | get-partition | Where-Object { $_.DriveLetter -like $letter } | ForEach-Object { $_.DiskNumber }
    "Select disk $s", "offline disk" | diskpart
    "Exit" | diskpart
}