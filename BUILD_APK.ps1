# FieldCheck APK Builder Script
# This script builds the Android APK with your custom backend IP

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "FieldCheck APK Builder" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Get the computer's IP address
Write-Host "Getting your computer's IP address..." -ForegroundColor Yellow
$ipConfig = ipconfig
$ipv4 = $ipConfig | Select-String "IPv4 Address" | Select-Object -First 1
$computerIp = $ipv4 -replace '.*:\s+', ''
$computerIp = $computerIp.Trim()

Write-Host "Found IP: $computerIp" -ForegroundColor Green
Write-Host ""

# Ask user to confirm or enter custom IP
Write-Host "Is this your computer's IP? (Y/n)" -ForegroundColor Yellow
$response = Read-Host

if ($response -eq 'n' -or $response -eq 'N') {
    Write-Host "Enter your computer's IP address:" -ForegroundColor Yellow
    $computerIp = Read-Host
}

$apiUrl = "http://$computerIp`:3002"
Write-Host ""
Write-Host "Building APK with Backend URL: $apiUrl" -ForegroundColor Green
Write-Host ""

# Navigate to flutter project
$flutterPath = "c:\Users\micha\OneDrive\Desktop\BSIT\BSIT4\Capstone 2\capstone_fieldcheck_4.0\capstone_fieldcheck_2.0\field_check"

# Build APK with custom API URL
Write-Host "Building release APK..." -ForegroundColor Yellow
cd $flutterPath
flutter build apk --release --dart-define=ANDROID_API_URL=$apiUrl

Write-Host ""
Write-Host "=====================================" -ForegroundColor Green
Write-Host "Build Complete!" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Green
Write-Host ""
Write-Host "APK Location: build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Cyan
Write-Host "Backend URL: $apiUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Transfer APK to your Android device"
Write-Host "2. Install it on your phone"
Write-Host "3. Make sure PM2 backend is running with: pm2 list"
Write-Host "4. Launch the app and login"
Write-Host ""
