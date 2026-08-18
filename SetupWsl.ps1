$medias = @{}
foreach($media in Get-CimInstance -ClassName Win32_PhysicalMedia | Select-Object Tag, SerialNumber){
    $medias.add($media.Tag, $media.SerialNumber)
}

foreach($drives in Get-CimInstance -query "SELECT * from Win32_DiskDrive"){
    if ( ($drives.Caption -ne 'ASMT CRCM535U32CIS SCSI Disk Device') -and
         ($drives.Caption -ne 'WD My Book 25EE USB Device') -and
         ($drives.Caption -ne 'WDC  WUH722016CLE6L4') ){
        continue
    }
    Write-Host $drives.Caption
    Write-Host $drives.DeviceID

    $deviceSerial = $medias[$drives.DeviceID]
    Write-Host $deviceSerial

    $deviceId = $drives.DeviceID.split('\')[-1]
    wsl --mount $drives.DeviceID --partition 1
    $symlinkname=wsl cat /mnt/wsl/${deviceId}p1/symlinkname
    if ($symlinkname -ne $null) {
        wsl ln -sfnv /mnt/wsl/${deviceId}p1 /home/tyamamoto/$symlinkname
    } else {
        Write-Host "symlinkname not found" -ForegroundColor DarkYellow
    }
}

wsl --mount "D:\wsl.vhdx" --vhd  --partition 1 --name dvhdx

$WSL2_IPV4=bash /home/tyamamoto/workspace/scripts/WSL-Ubuntu22.04/getip.sh
$HOST_IPV4="192.168.22.4"
$PORT="8061"
Write-Host $WSL2_IPV4
Write-Host $HOST_IPV4
Write-Host $PORT

# 古い設定を削除
netsh interface portproxy delete v4tov4 listenaddress=$HOST_IPV4 listenport=$PORT
# ホストIP:PORTへアクセスがあったら、WSL2_IP:PORTに転送
netsh interface portproxy add v4tov4 listenaddress=$HOST_IPV4 listenport=$PORT connectaddress=$WSL2_IPV4 connectport=$PORT
# ポートフォワード設定表示
netsh interface portproxy show v4tov4

exit
