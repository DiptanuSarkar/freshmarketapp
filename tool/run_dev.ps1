param(
    [string]$Device = ""
)

$configFile = "config/dev.json"
if (-not (Test-Path $configFile)) {
    Write-Error "Configuration file '$configFile' not found. Please create it from config/dev.example.json."
    exit 1
}

$flutterArgs = @("run", "--dart-define-from-file=$configFile")
if ($Device) {
    $flutterArgs += @("-d", $Device)
}

Write-Host "Running Flutter app with '$configFile'..." -ForegroundColor Cyan
flutter @flutterArgs
