$configFile = "config/dev.json"
if (-not (Test-Path $configFile)) {
    Write-Error "Configuration file '$configFile' not found. Please create it from config/dev.example.json."
    exit 1
}

Write-Host "Building debug APK with '$configFile'..." -ForegroundColor Cyan
flutter build apk --debug --dart-define-from-file=$configFile
