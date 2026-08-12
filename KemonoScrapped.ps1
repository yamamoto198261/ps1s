$PSDefaultParameterValues['*:Encoding'] = 'utf8'

# Everything 用 query
# path:Sites|path:temp  folder:|file:lnk 

$WsShell = New-Object -ComObject WScript.Shell

$mainSitesPath = (Read-Host "mainSitesPath")
$tempPixivPath = (Read-Host "tempPixivPath")
$cwd = (Read-Host "current working directory")
cd $cwd

# $mainSitesPath = $Args[0]
# $tempPixivPath = $Args[1]
# $targetName = $Args[2]

$children = @{}
foreach ($child in Get-ChildItem -Path .) {
    # Write-Host "V: $child"
    if ($child -match '^.* (?<id>\d{7,9})( \([dD]iscord\)| \(eh\))?$') {
        $children.Add($matches['id'], $child)
    } elseif ($child -match '^(dogvah ai )?(?<id>\d{7,9}) .*$') {
        $children.Add($matches['id'], $child)
    } elseif ($child -match '^.* p-(?<id>\d{6,7})$') {
        $children.Add($matches['id'], $child)
    } else {
        if ($child.PSIsContainer) {
            foreach ($file in Get-ChildItem -LiteralPath "$child") {
                if ($file -match '^(?<id>\d{7,9})_\d{3}\.\w+$') {
                    $children.Add($matches['id'], $child)
                    break
                } else {
                    Write-Host "E:     file name does not match pattern: $file" -ForegroundColor DarkYellow
                }
            }
        } else {
            if ($child -match '(?<id>\d{7,9})_\d{3}\.\w+$') {
                if (-Not ($children.ContainsKey($matches['id']))) {
                    $children.Add($matches['id'], $child)
                }
            } else {
                Write-Host "E:     file name does not match pattern: $child" -ForegroundColor DarkYellow
            }
        }
    }
}
Write-Host "I: Found children: $($children.Count)"

foreach ($child in $children.GetEnumerator() | Sort-Object { [Int]$_.Key }) {
    $targetName = $child.Value
    Write-Host "I: Processing $targetName"
    Write-Host "V:     ID: $($child.Key)"

    $src = "$targetName"
    $dest = "$mainSitesPath"
    # Write-Host "V:     move $src`n       to   $dest"
    Move-Item -LiteralPath "$src" -Destination "$dest" -ErrorAction Stop
    # Write-Host "V:     done"


    $refsDir = "$tempPixivPath\$targetName"
    # Write-Host "V:     mkdir $refsDir"
    $_ = New-Item -Path $refsDir -ItemType Directory -Force
    # Write-Host "V:     done"

    $refs = "$targetName.lnk"
    # Write-Host "V:     link $refsDir\$refs`n       to   $dest\$targetName"
    $Shortcut = New-Item $refsDir\$refs -ItemType File -Force
    $Shortcut = (New-Object -ComObject Shell.Application).NameSpace($refsDir).Items().Item($refs).GetLink
    $Shortcut.Path = "$dest\$targetName"
    $Shortcut.Save("$refsDir\$refs")
    # Write-Host "V:     done"
}
