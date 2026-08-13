param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$RootPath
)

$ErrorActionPreference = 'Continue'

try {
    $rootDir = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path
} catch {
    Write-Error "Directory not found: $RootPath"
    exit 1
}

if (-not (Test-Path -LiteralPath $rootDir -PathType Container)) {
    Write-Error "Directory not found: $rootDir"
    exit 1
}

$logFile = Join-Path (Get-Location).Path ("{0}_{1}.log" -f (Split-Path $rootDir -Leaf), (Get-Date -Format yyyyMMddHHmmss))
New-Item -Path $logFile -ItemType File -Force | Out-Null

function Write-Log {
    param([string]$Message)
    Add-Content -Path $logFile -Value $Message
    Write-Host $Message
}

function Get-ArchiveFiles {
    param([string]$Directory)
    Get-ChildItem -LiteralPath $Directory -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.zip', '.7z', '.rar' }
}

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-EncryptedArchive {
    param([string]$ArchivePath)

    if (-not $has7z) { return $false }

    $listOutput = & 7z l -slt -p- -bso0 $ArchivePath 2>&1
    if ($LASTEXITCODE -ne 0) { return $false }

    return ($listOutput -match 'Encrypted\s*=\s*\+')
}

$has7z = Test-Command 7z
$hasUnzip = Test-Command unzip
$hasExpandArchive = Test-Command Expand-Archive

function Extract-Archive {
    param(
        [string]$ArchivePath,
        [string]$Destination,
        [switch]$SkipExisting
    )

    $lowerPath = $ArchivePath.ToLower()
    if ($lowerPath.EndsWith('.zip')) {
        if (Test-EncryptedArchive -ArchivePath $ArchivePath) {
            Write-Log "Skipped password-protected archive: $ArchivePath"
            return 1
        }

        if ($has7z) {
            $mode = if ($SkipExisting) { @('x', '-aos', '-bso0', '-p-') } else { @('x', '-y', '-bso0', '-p-') }
            $processOutput = & 7z @mode "-o$Destination" $ArchivePath 2>&1
            $exitCode = $LASTEXITCODE
            if ($exitCode -le 1) { return 0 }
            if ($processOutput -match 'password|wrong password|encrypted') {
                Write-Log "Skipped password-protected archive: $ArchivePath"
                return 1
            }
            return $exitCode
        }

        if ($hasExpandArchive) {
            try {
                Expand-Archive -Path $ArchivePath -DestinationPath $Destination -Force
                return 0
            } catch {
                return 1
            }
        }

        if ($hasUnzip) {
            $args = if ($SkipExisting) { '-n' } else { '' }
            & unzip $args $ArchivePath -d $Destination
            return $LASTEXITCODE
        }

        Throw "No supported ZIP extractor found for '$ArchivePath'"
    }

    if ($lowerPath.EndsWith('.7z') -or $lowerPath.EndsWith('.rar')) {
        if (-not $has7z) {
            Throw "7z is required to extract 7z/rar archives on this system"
        }

        if (Test-EncryptedArchive -ArchivePath $ArchivePath) {
            Write-Log "!! Skipped password-protected archive: $ArchivePath"
            return 1
        }

        $mode = if ($SkipExisting) { @('x', '-aos', '-bso0', '-p-') } else { @('x', '-y', '-bso0', '-p-') }
        $processOutput = & 7z @mode "-o$Destination" $ArchivePath 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -le 1) { return 0 }
        if ($processOutput -match 'password|wrong password|encrypted') {
            Write-Log "!! Skipped password-protected archive: $ArchivePath"
            return 1
        }
        return $exitCode
    }

    Throw "Unsupported archive format: '$ArchivePath'"
}

function Remove-MetaFiles {
    param([string]$Directory)

    $metaItems = @('__MACOSX', 'Thumbs.db', '.DS_Store', 'desktop.ini')
    foreach ($item in $metaItems) {
        $target = Join-Path $Directory $item
        if (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Removed $target"
        }
    }
}

function Move-ChildItemsUpOneLevel {
    param(
        [string]$ChildDir,
        [string]$ParentDir
    )

    Get-ChildItem -LiteralPath $ChildDir -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Move-Item -LiteralPath $_.FullName -Destination $ParentDir -Force
    }
    Remove-Item -LiteralPath $ChildDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-RelativePathCompat {
    param(
        [string]$FromPath,
        [string]$ToPath
    )

    $fromFull = [System.IO.Path]::GetFullPath($FromPath).TrimEnd('\', '/')
    $toFull = [System.IO.Path]::GetFullPath($ToPath).TrimEnd('\', '/')

    if ($fromFull -eq $toFull) {
        return '.'
    }

    $fromUri = New-Object System.Uri(($fromFull + [System.IO.Path]::DirectorySeparatorChar))
    $toUri = New-Object System.Uri(($toFull + [System.IO.Path]::DirectorySeparatorChar))

    $relative = [System.Uri]::UnescapeDataString($fromUri.MakeRelativeUri($toUri).ToString())
    return ($relative -replace '/', '\')
}

function Get-RelativeSubdirectories {
    param([string]$BaseDirectory)

    if (-not (Test-Path -LiteralPath $BaseDirectory -PathType Container)) {
        return @()
    }

    Get-ChildItem -LiteralPath $BaseDirectory -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Sort-Object FullName | ForEach-Object {
            Get-RelativePathCompat -FromPath $BaseDirectory -ToPath $_.FullName
        }
}

$trashRoot = 'D:\extract_single_archive_trash'

Get-ChildItem -LiteralPath $rootDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $userDir = $_
    Get-ChildItem -LiteralPath $userDir.FullName -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $articleDir = $_
        Write-Log $articleDir.FullName

        $archives = Get-ArchiveFiles $articleDir.FullName
        if ($archives.Count -eq 1) {
            $archive = $archives[0]
            $exitCode = Extract-Archive -ArchivePath $archive.FullName -Destination $articleDir.FullName
            if ($exitCode -eq 0) {
                $trashDir = Join-Path $trashRoot $userDir.Name
                $trashDir = Join-Path $trashDir $articleDir.Name
                New-Item -Path $trashDir -ItemType Directory -Force | Out-Null
                Move-Item -LiteralPath $archive.FullName -Destination $trashDir -Force

                Remove-MetaFiles $articleDir.FullName

                $items = Get-ChildItem -LiteralPath $articleDir.FullName -Force -ErrorAction SilentlyContinue
                if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
                    if ($userDir.Name -eq '98581600_Axiah') {
                        $subdirs = Get-RelativeSubdirectories $articleDir.FullName
                        if ($subdirs.Count -eq 3 -and $subdirs -eq @('jpg', 'jpg\\HD', 'jpg\\jpg')) {
                            $jpgDir = Join-Path $articleDir.FullName 'jpg'
                            $hdDir = Join-Path $jpgDir 'HD'
                            $jpgJpgDir = Join-Path $jpgDir 'jpg'

                            if (Test-Path -LiteralPath $hdDir) {
                                Move-ChildItemsUpOneLevel -ChildDir $hdDir -ParentDir $articleDir.FullName
                                Remove-Item -LiteralPath $hdDir -Recurse -Force -ErrorAction SilentlyContinue
                            }
                            if (Test-Path -LiteralPath $jpgJpgDir) {
                                Remove-Item -LiteralPath $jpgJpgDir -Recurse -Force -ErrorAction SilentlyContinue
                            }
                            if (Test-Path -LiteralPath $jpgDir) {
                                Remove-Item -LiteralPath $jpgDir -Force -ErrorAction SilentlyContinue
                            }
                        }
                    } else {
                        Move-ChildItemsUpOneLevel -ChildDir $items[0].FullName -ParentDir $articleDir.FullName
                    }
                }
            } else {
                Write-Log '!! fail to extract. keep archive.'
                Write-Log $articleDir.FullName
            }
            Write-Log '======== extract done.'
        } elseif ($userDir.Name -eq '127263913_ChocoPizza') {
            foreach ($archive in $archives) {
                $exitCode = Extract-Archive -ArchivePath $archive.FullName -Destination $articleDir.FullName -SkipExisting
                if ($exitCode -eq 0) {
                    $trashDir = Join-Path $trashRoot $userDir.Name
                    $trashDir = Join-Path $trashDir $articleDir.Name
                    New-Item -Path $trashDir -ItemType Directory -Force | Out-Null
                    Move-Item -LiteralPath $archive.FullName -Destination $trashDir -Force
                } else {
                    Write-Log '!! fail to extract. keep archive.'
                    Write-Log $articleDir.FullName
                }
                Write-Log '======== extract done.'
            }
        }
    }
}

# Get-ArchiveFiles $rootDir | ForEach-Object {
#     Write-Log $_.FullName
# }
