@echo off
REM Test the login endpoint
echo Testing backend login API...
echo.

REM Test 1: Admin login
echo ======================================
echo Test 1: Admin Login
echo ======================================
curl -X POST http://localhost:3002/api/users/login ^
  -H "Content-Type: application/json" ^
  -d "{\"identifier\":\"admin@example.com\",\"password\":\"Admin@123\"}"
echo.
echo.

REM Test 2: Employee login
echo ======================================
echo Test 2: Employee Login
echo ======================================
curl -X POST http://localhost:3002/api/users/login ^
  -H "Content-Type: application/json" ^
  -d "{\"identifier\":\"employee1\",\"password\":\"employee123\"}"
echo.
echo.

REM Test 3: Get health check
echo ======================================
echo Test 3: Health Check
echo ======================================
curl -X GET http://localhost:3002/api/health
echo.
