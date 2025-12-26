#!/usr/bin/env pwsh

# Test MongoDB connection via backend API
Write-Host "🧪 Testing MongoDB Connection via Backend API" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host ""

# Test 1: Health Check (basic connectivity)
Write-Host "Test 1: Backend Health Check" -ForegroundColor Cyan
try {
    $response = Invoke-RestMethod -Uri "http://localhost:3002/api" -Method Get -TimeoutSec 5 -ErrorAction Stop
    Write-Host "✅ Backend is responding at http://localhost:3002" -ForegroundColor Green
} catch {
    Write-Host "❌ Backend not responding. Make sure 'npm start' is running" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Test 2: Admin Login
Write-Host "Test 2: Admin Login with MongoDB" -ForegroundColor Cyan
$loginBody = @{
    email = "admin@example.com"
    password = "Admin@123"
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod `
        -Uri "http://localhost:3002/api/users/login" `
        -Method Post `
        -ContentType "application/json" `
        -Body $loginBody `
        -TimeoutSec 5

    Write-Host "✅ Admin login successful!" -ForegroundColor Green
    Write-Host "   User: $($response.user.email)" -ForegroundColor Green
    Write-Host "   Role: $($response.user.role)" -ForegroundColor Green
    Write-Host "   Token received: $($response.token.Substring(0, 20))..." -ForegroundColor Green
} catch {
    Write-Host "❌ Admin login failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Test 3: Employee Login
Write-Host "Test 3: Employee Login with MongoDB" -ForegroundColor Cyan
$employeeLoginBody = @{
    email = "employee1@example.com"
    password = "employee123"
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod `
        -Uri "http://localhost:3002/api/users/login" `
        -Method Post `
        -ContentType "application/json" `
        -Body $employeeLoginBody `
        -TimeoutSec 5

    Write-Host "✅ Employee login successful!" -ForegroundColor Green
    Write-Host "   User: $($response.user.email)" -ForegroundColor Green
    Write-Host "   Role: $($response.user.role)" -ForegroundColor Green
} catch {
    Write-Host "❌ Employee login failed" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host "🎉 All MongoDB tests passed!" -ForegroundColor Green
Write-Host "✅ Backend is connected to MongoDB Atlas" -ForegroundColor Green
Write-Host "✅ Authentication working with cloud database" -ForegroundColor Green
Write-Host "✅ Ready for Flutter app testing or Render deployment" -ForegroundColor Green
Write-Host ""
