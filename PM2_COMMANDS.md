# PM2 Server Management Guide

Your FieldCheck backend is now running with PM2. Here are the essential commands:

## Quick Commands

### Check Server Status
```powershell
node "C:\Users\micha\AppData\Roaming\npm\node_modules\pm2\bin\pm2" list
```
Shows if the server is online, CPU usage, and memory usage.

### View Server Logs
```powershell
node "C:\Users\micha\AppData\Roaming\npm\node_modules\pm2\bin\pm2" logs fieldcheck-backend
```
View real-time logs (press Ctrl+C to exit)

### View Last 50 Lines of Logs
```powershell
node "C:\Users\micha\AppData\Roaming\npm\node_modules\pm2\bin\pm2" logs fieldcheck-backend --lines 50
```

### Stop the Server
```powershell
node "C:\Users\micha\AppData\Roaming\npm\node_modules\pm2\bin\pm2" stop fieldcheck-backend
```

### Restart the Server
```powershell
node "C:\Users\micha\AppData\Roaming\npm\node_modules\pm2\bin\pm2" restart fieldcheck-backend
```

### Restart All Processes
```powershell
node "C:\Users\micha\AppData\Roaming\npm\node_modules\pm2\bin\pm2" restart all
```

### Delete Process from PM2
```powershell
node "C:\Users\micha\AppData\Roaming\npm\node_modules\pm2\bin\pm2" delete fieldcheck-backend
```

---

## Current Status

✅ **Server is running via PM2**
- **Name:** fieldcheck-backend
- **Port:** http://localhost:3002
- **Database:** MongoDB Atlas (Connected)
- **Memory:** ~73 MB
- **Status:** Online

---

## What PM2 Does

1. **Keeps Server Running** - If the server crashes, PM2 automatically restarts it
2. **Daemonized** - Runs in the background so you don't need to keep a terminal open
3. **Persistent** - Survives terminal window closures
4. **Monitoring** - Shows memory and CPU usage
5. **Logging** - Saves all logs in `C:\Users\micha\.pm2\logs\`

---

## Tips

- The server will continue running even if you close the terminal window
- You can safely restart your computer, and the server will restart automatically (if you configure PM2 to start on boot)
- Check logs anytime to debug issues
- The server is accessible at `http://localhost:3002` from your app

---

## Making PM2 Start on Boot (Optional)

To have PM2 start automatically when Windows restarts:

```powershell
node "C:\Users\micha\AppData\Roaming\npm\node_modules\pm2\bin\pm2" startup
node "C:\Users\micha\AppData\Roaming\npm\node_modules\pm2\bin\pm2" save
```

This will ensure your backend server runs automatically after a Windows restart.
