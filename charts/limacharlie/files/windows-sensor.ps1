$ErrorActionPreference = 'Stop'
# The progress bar makes Invoke-WebRequest crawl on Windows PowerShell 5.1.
$ProgressPreference = 'SilentlyContinue'
$service = 'rphcpsvc'

if (-not (Get-Service $service -ErrorAction SilentlyContinue)) {
  Write-Host "Installing the LimaCharlie sensor from $env:LC_INSTALLER_URL"
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $installer = Join-Path $env:TEMP 'lc_sensor.exe'
  Invoke-WebRequest -UseBasicParsing -Uri $env:LC_INSTALLER_URL -OutFile $installer
  & $installer -i $env:LC_INSTALLATION_KEY
  if ($LASTEXITCODE -ne 0) { throw "lc_sensor.exe -i exited with $LASTEXITCODE" }
  Remove-Item $installer -Force
}

# If the service cannot be started the script throws, the container exits and
# the pod shows up as crash-looping instead of silently reporting healthy.
while ($true) {
  if ((Get-Service $service).Status -ne 'Running') {
    Write-Host "$service is not running, starting it"
    Start-Service $service
  }
  Start-Sleep -Seconds 60
}
