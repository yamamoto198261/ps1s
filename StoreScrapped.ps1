$PSDefaultParameterValues['*:Encoding'] = 'utf8'

$dbJsonPath = "D:\Main\region3\KH\Sites\StoreScrapped.json"

$mainSitesPath = "D:\Main\region3\KH\Sites"
$tempPixivPath = "D:\Main\region3\temp\未\pixiv"
$waitKemonoPath = "D:\Main\region3\temp\kemono待ち"

$workPixivPath = "D:\Main_work\pixiv"

$zipCheck = Get-ChildItem -Path $workPixivPath -Recurse -Filter "*.zip"
if ($null -ne $zipCheck) {
    Write-Host "E: zip exist under: $workPixivPath" -ForegroundColor DarkYellow
    exit 1
}

$WsShell = New-Object -ComObject WScript.Shell

$db = (Get-Content $dbJsonPath | ConvertFrom-Json)
# Write-Host $db

$mainUserAncestors = @{}
foreach($freqDir in "pixiv_freq") {
    foreach($parentDir in (Get-ChildItem "$mainSitesPath\$freqDir" | Where-Object { $_.PSIsContainer })) {
        if ("$parentDir" -eq "lnk") { continue }
        if ("$parentDir" -eq "removed") { continue }
        if ("$parentDir" -eq "お気に入り外") { continue }

        foreach($userDir in (Get-ChildItem "$mainSitesPath\$freqDir\$parentDir" | Where-Object { $_.PSIsContainer })) {
            $m = ($userDir -match '^(?<id>\d+)_(?<name>.*)')
            if ( -not $m) {
                Write-Host "E:   dir name does not match pattern: $userDir" -ForegroundColor DarkYellow
                continue
            }
            $mainUserAncestors.Add($matches['id'], @{"userDir" = "$userDir"; "ancestors" = "$freqDir\$parentDir"})
        }
    }
}
# $mainUserAncestors

$autoSkip = $true
if ((Read-Host "Auto Skip? (y/n)") -ne "y") {
    $autoSkip = $false
}

foreach($userDir in Get-ChildItem -LiteralPath $workPixivPath |
                    Sort-Object -Property LastWriteTime) {
    Write-Host "I: START $userDir"
    $m = ($userDir -match '(?<id>\d+)_(?<name>.+)')
    if ( -not $m) {
        Write-Host "E:   dir name does not match pattern: $userDir" -ForegroundColor DarkYellow
        continue
    }
    $userId = $matches['id']
    $userName = $matches['name']

    $userInfo = $db.$userId
    if ($userInfo -eq $null) {
        Write-Host "E:   userId not registerred in db: $userId" -ForegroundColor DarkYellow
        continue
    }

    if (($userInfo.skip -ne $null) -and ($userInfo.skip)) {
        Write-Host "I:   skip flag is True: $userDir" -ForegroundColor DarkYellow
        if ($autoSkip) {
            Write-Host "I:   auto skip is True. continue" -ForegroundColor DarkYellow
            continue
        }
        if ((Read-Host "exec? (y: exec/n: skip)") -ne "y") {
            continue
        }
    }

    if ($userInfo.altId -ne $null) {
        $userId = $userInfo.altId
        Write-Host "I:   use altId: $userId"
    }

    if ($mainUserAncestors["$userId"] -eq $null) {
        Write-Host "E:   userDir with userId not exist: $userId" -ForegroundColor DarkYellow
        continue
    }
    $targetUserDir = $mainUserAncestors["$userId"].userDir
    # Write-Host "V:   targetUserDir: $targetUserDir"

    $targetMainAncestor = $mainUserAncestors["$userId"].ancestors
    # Write-Host "V:   targetMainAncestor: $targetMainAncestor"

    if ($userInfo.subDir -ne $null) {
        $targetUserDir = "$targetUserDir\$($userInfo.subDir)"
        # Write-Host "V:   targetUserDir with subDir: $targetUserDir"
    }

    foreach($article in Get-ChildItem -LiteralPath "$workPixivPath\$userDir") {
        Write-Host "I:   START $article"

        $src = "$workPixivPath\$userDir\$article"
        $dest = "$mainSitesPath\$targetMainAncestor\$targetUserDir"

        $pixivArticles = @{}
        if ($article.PSIsContainer) {
            foreach ($item in (Get-ChildItem -LiteralPath "$src")) {
                if ($item.Name -match '^(?<id>\d+_p)\d+\.\w+$') {
                    if (-not $pixivArticles.ContainsKey($matches['id'])) {
                        $pixivArticles.Add($matches['id'], "$article $($matches['id'])")
                    }
                } elseif ($item.Name -match '^(?<id>\d+)_ugoira\d+x\d+') {
                    if (-not $pixivArticles.ContainsKey("$($matches['id'])_p")) {
                        $pixivArticles.Add("$($matches['id'])_p", "$article $($matches['id'])_p")
                    }
                } elseif ($item.Name -match '^(?<id>work_\d+_\d+)_\d+\.\w+$') {
                    if (-not $pixivArticles.ContainsKey($matches['id'])) {
                        $pixivArticles.Add($matches['id'], "$article $($matches['id'])")
                    }
                } else {
                    Write-Host "E:     article name does not match pattern: $article" -ForegroundColor DarkYellow
                    continue
                }
            }
        } else {
            if ($article.Name -match '^(?<title>.+) (?<id>\d+_p)\d+\.\w+$') {
                $pixivArticles.Add($matches['id'], "$($matches['title']) $($matches['id'])")
            } else {
                Write-Host "E:     article name does not match pattern: $article" -ForegroundColor DarkYellow
                continue
            }
        }

        if ($pixivArticles.Count -ne 0) {
            # Write-Host "V:     move $src`n       to   $dest"
            try  {
                Move-Item -LiteralPath "$src" -Destination "$dest" -ErrorAction Stop
            } catch {
                if (($_.Exception.Message -match "既に存在するファイルを作成することはできません") -or
                    ($_.Exception.Message -match "Cannot create a file when that file already exists")){
                    Write-Host "I:     already exit: $article"
                    Get-ChildItem -LiteralPath "$src" -Recurse | Move-Item -Destination "$dest/$article"
                    if ((Get-ChildItem -LiteralPath "$src").Count -eq 0) {
                        Remove-Item -LiteralPath "$src"
                    } else {
                        Write-Host "E:     not empty. fail to move children recursivly?" -ForegroundColor DarkYellow
                    }
                } else {
                    throw $_
                }
            }
            # Write-Host "V:     done"
        } else {
            Write-Host "E:     nothing to move." -ForegroundColor DarkYellow
        }

        foreach ($id in $pixivArticles.Keys) {
            $refsDir = "$tempPixivPath\$targetUserDir\$($pixivArticles[$id])"
            $refs = $article.Basename + ".lnk"

            # Write-Host "V:     link $refsDir\$refs`n       to   $dest\$article"
            if (-not (Test-Path -LiteralPath $refsDir)) {
                $_ = New-Item -Path "$refsDir" -ItemType Directory -Force
            }
            $Shortcut = New-Item $refsDir\$refs -ItemType File -Force
            $Shortcut = (New-Object -ComObject Shell.Application).NameSpace($refsDir).Items().Item($refs).GetLink
            $Shortcut.Path = "$dest\$article"
            $Shortcut.Save("$refsDir\$refs")
            # Write-Host "V:     done"

            if (($userInfo.waitKemono -ne $null) -and ($userInfo.waitKemono)) {
                $refsDir = "$waitKemonoPath\$targetUserDir"
                $refsBase = "$article $id"
                if (-not $refsBase -eq $pixivArticles[$id]) {
                    # means, this article is the file
                    $refsBase = $article.Basename
                }

                $refsIndex = 1
                $refs = "$refsBase.lnk"
                while (Test-Path -LiteralPath "$refsDir\$refs") {
                    $refs = "$refsBase ($((++$refsIndex))).lnk"
                }

                # Write-Host "V:     link $refsDir\$refs`n       to   $dest\$article"
                $Shortcut = New-Item $refsDir\$refs -ItemType File -Force
                $Shortcut = (New-Object -ComObject Shell.Application).NameSpace($refsDir).Items().Item($refs).GetLink
                $Shortcut.Path = "$dest\$article"
                $Shortcut.Save("$refsDir\$refs")
                # Write-Host "V:     done"
            }
        }

        # Write-Host "V:   END   $article"
    }

    Write-Host "I:   remove userDir"
    if ((Get-ChildItem -LiteralPath "$workPixivPath\$userDir").Count -eq 0) {
        Remove-Item -LiteralPath "$workPixivPath\$userDir"
        # Write-Host "V:   done"
    } else {
        Write-Host "E:   not empty" -ForegroundColor DarkYellow
    }
}
