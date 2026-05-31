Stop-Process -Name love -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400
Start-Process "C:\Program Files\LOVE\love.exe" -ArgumentList "C:\Users\Ben\Documents\bridge" -RedirectStandardError "C:\Users\Ben\Documents\bridge\_err.txt"
Start-Sleep -Milliseconds 1500
$p = Get-Process love -ErrorAction SilentlyContinue
if (-not $p) {
    Write-Output "CRASHED"
    Get-Content "C:\Users\Ben\Documents\bridge\_err.txt" -ErrorAction SilentlyContinue
    exit
}
