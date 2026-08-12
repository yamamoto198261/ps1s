$PSDefaultParameterValues['*:Encoding'] = 'utf8'

$WsShell = New-Object -ComObject WScript.Shell

$mainSitesPath = "D:\Main\KH\Sites"
$tempPixivPath = "D:\Main_work\未\pixiv"

$dbJsonPath = "D:\Main\KH\Sites\StoreScrapped.json"

$cwd = Get-Location
# Write-Host "V: current working directory: $cwd"
$dirName = [System.IO.Path]::GetFileName($cwd)
# Write-Host "V: current directory name: $dirName"

$db = (Get-Content $dbJsonPath | ConvertFrom-Json)
# Write-Host $db

$mainUserAncestors = @{}
foreach($freqDir in "pixiv_freq", "pixiv_rare") {
    foreach($parentDir in (Get-ChildItem "$mainSitesPath\$freqDir" | Where-Object { $_.PSIsContainer })) {
        foreach($userDir in (Get-ChildItem "$mainSitesPath\$freqDir\$parentDir" | Where-Object { $_.PSIsContainer })) {
            $mainUserAncestors.Add("$userDir", "$freqDir\$parentDir")
        }
    }
}
foreach($serviceDir in "Deviant Art", "Fanbox", "Fantia", "Gumroad", "Patreon") {
    foreach($userDir in (Get-ChildItem "$mainSitesPath\$serviceDir" | Where-Object { $_.PSIsContainer })) {
        $mainUserAncestors.Add("$userDir", "$serviceDir")
    }
}
# $mainUserAncestors

$cnt = 0
$stopMark = $false
$done = 1113
foreach($userDir in Get-ChildItem -LiteralPath $tempPixivPath) {
    if ($cnt -le $done) {
        $cnt++
        continue
    } elseif ($cnt -gt $done+1) {
        Write-Host "I:   STOP at $userDir | $cnt" -ForegroundColor DarkYellow
        break
    }

    Write-Host "I: START $userDir | $cnt" -ForegroundColor Yellow
    $m = ($userDir -match '(?<id>\d+)_(?<name>.+)')
    if ( -not $m) {
        Write-Host "E:   dir name does no tmatch pattern: $userDir" -ForegroundColor DarkYellow
        exit 1
    }

    $userInfo = $db.$userDir
    if ($userInfo -ne $null) {
        if ($userInfo.altName -eq $null) {
            $targetUserDir = $userDir
        } else {
            $targetUserDir = $userInfo.altName
        }

        if ($userInfo.mainAncestor -ne $null) {
            $targetMainAncestor = $userInfo.mainAncestor
        } elseif ($mainUserAncestors["$targetUserDir"] -ne $null) {
            $targetMainAncestor = $mainUserAncestors["$targetUserDir"]
        } else {
            Write-Host "E:   no info of Ancestor" -ForegroundColor DarkYellow
            exit 1
        }
    } elseif ($mainUserAncestors["$userDir"] -ne $null) {
        $targetUserDir = $userDir
        $targetMainAncestor = $mainUserAncestors["$targetUserDir"]
    } else {
        Write-Host "E:   userDir not found in db/mainUserAncestors: $userDir" -ForegroundColor DarkYellow
        exit 1
    }
    Write-Host "V:   targetMainAncestor: $targetMainAncestor"
    Write-Host "V:   targetUserDir: $targetUserDir"

    $acnt = 0
    :articleLoop foreach($article in Get-ChildItem -LiteralPath "$tempPixivPath\$userDir") {
        if ($acnt -lt 1) {
        } else {
            # break
        }
        Write-Host "I:   START $article"

        $dest = "$mainSitesPath\$targetMainAncestor\$targetUserDir\$article"
        # check dest exists
        if (-not (Test-Path -LiteralPath $dest)) {
            Write-Host "E:     destination does not exist: $dest" -ForegroundColor DarkYellow
            $stopMark = $true
            continue
        }

        if ($article.PSIsContainer) {
            $pixivArticles = @{}
            $kemonoScrapArticles = @{}
            $othersCount = 0
            foreach ($item in (Get-ChildItem -LiteralPath "$tempPixivPath\$userDir\$article")) {
                # Write-Host "V:     START $tempPixivPath\$userDir\$article\$item"
                if ($item.Name -match '^(?<id>\d+)_p\d+\.\w+$') {
                    if (-not $pixivArticles.ContainsKey($matches['id'])) {
                        $pixivArticles.Add($matches['id'], $item.LastWriteTime)
                    }
                    continue
                }
                if ($item.Name -match '^(?<id>\d{6,9})_\d{3}\.\w+$') {
                    if (-not $kemonoScrapArticles.ContainsKey($matches['id'])) {
                        $kemonoScrapArticles.Add($matches['id'], $item.LastWriteTime)
                    }
                    continue
                }
                $othersCount++
            }
            Write-Host "I:     Found p: $($pixivArticles.Count) k: $($kemonoScrapArticles.Count) o: $othersCount"

            $subArticles = @{}
            if ($pixivArticles.Count -ne 0 -and $kemonoScrapArticles.Count -eq 0 -and $othersCount -eq 0) {
                $dirSuffix = "_p"
                $subArticles = $pixivArticles
            } elseif ($pixivArticles.Count -eq 0 -and $kemonoScrapArticles.Count -ne 0 -and $othersCount -eq 0) {
                $dirSuffix = ""
                $subArticles = $kemonoScrapArticles
            } elseif ($pixivArticles.Count -eq 0 -and $kemonoScrapArticles.Count -eq 0 -and $othersCount -ne 0) {
                if ($article -match '^.+ (?<id>\d{6,9})$' -or $article -match '^(?<id>\d{6,9}) .+$' -or $article -match '^.+ \(eh\)$' -or $article -match '^.+ \(discord\)$' -or $article -match '^dogvah ai (?<id>\d{6,9}) .+$') {
                    # do nothing to keep subArticles empty
                } else {
                   Write-Host "E:     not match dirname with kemotno id pattern. skip: $article" -ForegroundColor DarkYellow
                    if ((Read-Host "exec? (y/n)") -ne "y") {
                        continue
                    }
                    # do nothing to keep subArticles empty
                }
            } else {
                Write-Host "E:     mixed. skip: $article" -ForegroundColor DarkYellow
                if ((Read-Host "exec? (y/n)") -ne "y") {
                    continue
                }
                # do nothing to keep subArticles empty
            }

            try  {
                if ($subArticles.Count -eq 0) {
                    $lastWriteTime = $article.LastWriteTime

                    foreach ($child in (Get-ChildItem -LiteralPath "$tempPixivPath\$userDir\$article") ) {
                        Remove-Item -LiteralPath $child.FullName -Force -Recurse
                    }

                    $refs = "$article.lnk"
                    # Write-Host "V:       link $($article.FullName)\$refs`n         to   $dest"
                    $Shortcut = New-Item "$($article.FullName)\$refs" -ItemType File -Force
                    $Shortcut = (New-Object -ComObject Shell.Application).NameSpace($($article.FullName)).Items().Item($refs).GetLink
                    $Shortcut.Path = "$dest"
                    $Shortcut.Save("$($article.FullName)\$refs")
                    # Write-Host "V:       done"

                    $article.LastWriteTime = $lastWriteTime
                } else {
                    foreach ($subArticle in $subArticles.GetEnumerator() | Sort-Object { [Int]$_.Key }) {
                        Write-Host "I:     Processing $($subArticle.Key)"

                        $subArticleDirPath = "$tempPixivPath\$userDir\$article $($subArticle.Key)$dirSuffix"
                        # Write-Host "V:       mkdir $subArticleDirPath"
                        $subArticleDir = New-Item -Path $subArticleDirPath -ItemType Directory -Force
                        # Write-Host "V:       done"

                        $refs = "$article.lnk"
                        # Write-Host "V:       link $subArticleDirPath\$refs`n         to   $dest"
                        $Shortcut = New-Item $subArticleDirPath\$refs -ItemType File -Force
                        $Shortcut = (New-Object -ComObject Shell.Application).NameSpace($subArticleDirPath).Items().Item($refs).GetLink
                        $Shortcut.Path = "$dest"
                        $Shortcut.Save("$subArticleDirPath\$refs")
                        # Write-Host "V:       done"

                        $subArticleDir.LastWriteTime = $subArticle.Value
                    }

                    # Write-Host "V:     remove $tempPixivPath\$userDir\$article"
                    Remove-Item -LiteralPath "$tempPixivPath\$userDir\$article" -Force -Recurse
                    # Write-Host "V:     done"
                }
            } catch {
                $stopMark = $true
                throw $_
                exit 1
            }
        } else {
            $articleBase = [System.IO.Path]::GetFileNameWithoutExtension($article.Name)
            Write-Host "I:     Processing $($articleBase)"

            $refsDirPath = "$tempPixivPath\$userDir\$articleBase"
            # Write-Host "V:       mkdir $refsDirPath"
            $refsDir = New-Item -Path $refsDirPath -ItemType Directory -Force
            # Write-Host "V:       done"

            $refs = "$articleBase.lnk"
            # Write-Host "V:       link $refsDirPath\$refs`n         to   $dest"
            $Shortcut = New-Item $refsDirPath\$refs -ItemType File -Force
            $Shortcut = (New-Object -ComObject Shell.Application).NameSpace($refsDirPath).Items().Item($refs).GetLink
            $Shortcut.Path = "$dest"
            $Shortcut.Save("$refsDirPath\$refs")
            # Write-Host "V:       done"

            $refsDir.LastWriteTime = $article.LastWriteTime

            # Write-Host "V:       remove $tempPixivPath\$userDir\$article"
            Remove-Item -LiteralPath "$tempPixivPath\$userDir\$article" -Force
            # Write-Host "V:       done"
        }
        $acnt++
    }
    if ($stopMark) {
        Write-Host "I:   STOP MARKED at $userDir | $cnt" -ForegroundColor DarkYellow
        if ((Read-Host "continue? (y/n)") -ne "y") {
            break
        }
        $stopMark = $false
    }
    $cnt++
}
