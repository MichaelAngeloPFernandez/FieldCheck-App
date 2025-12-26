# 🗺️ MAP SCREEN BUTTON GUIDE - Quick Reference

## Three Floating Action Buttons Explained

```
┌─────────────────────────────────────────────────────────┐
│                      MAP SCREEN                         │
│                                                         │
│  [Map Display]                        [3 Buttons ▶]   │
│  - Shows geofence circles or tasks                     │
│  - Displays employee location (you)                    │
│  - Red pin: Outside geofence                           │
│  - Blue pin: Inside geofence                           │
│  - Purple markers: Tasks                               │
│                                                         │
│                          ▲                             │
│                          │                             │
│                    [BUTTON 1]                          │
│                  Center Location                       │
│                (my_location icon)                      │
│                                                         │
│                          ▲                             │
│                          │                             │
│                    [BUTTON 2]                          │
│                  Toggle View                           │
│            (location_on ↔ assignment)                  │
│                                                         │
│                          ▲                             │
│                          │                             │
│                    [BUTTON 3]                          │
│                  Toggle Filter                         │
│              (lock ↔ public icon)                      │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## BUTTON 1: Center Location 🎯

### Icon: `my_location`
### Tooltip: "Center map on your current location"

**What it does**:
- Instantly centers the map on your current GPS location
- Refreshes your geofence assignment status
- Useful when map has scrolled away

**When to use**:
- When you can't find yourself on the map
- When location feels stuck or outdated
- After moving to a new location

**How it works**:
1. Click the button
2. Map zooms and centers on your GPS position
3. Updates geofence assignment status
4. Shows if you're inside or outside

**Result**: 
```
Before:  Map showing other area, location unknown
After:   Map centered on you, status updated
```

---

## BUTTON 2: Toggle View 📍

### Icon: `location_on` ↔ `assignment`
### Tooltip: Changes dynamically
- **In Geofence Mode**: "Show nearby tasks"
- **In Task Mode**: "Show geofence areas"

**What it does**:
- Switches between TWO different map views
- Geofence View: Shows work area boundaries
- Task View: Shows assignments on map

**When to use**:
- Click to switch between geofences and tasks
- Use geofence view to understand work area
- Use task view to see location-based tasks

**How it works**:

**Geofence View** (default):
```
Map shows:
✓ Geofence circles (work areas)
✓ Your location (blue/red pin)
✓ Geofence names and radius
✗ Tasks hidden
```

**Task View**:
```
Map shows:
✓ Task markers (purple icons)
✓ Task status colors
✓ Your location (blue/red pin)
✗ Geofence circles hidden
```

**Result**:
```
Click button → View switches → Shows different data
```

---

## BUTTON 3: Toggle Filter 🔒

### Icon: `lock` ↔ `public`
### Tooltip: Changes dynamically
- **Locked**: "Show all geofences"
- **Unlocked**: "Show assigned only"

**What it does**:
- Filters which geofences/tasks are visible
- Locked = Only YOUR assigned geofences
- Unlocked = ALL geofences in system

**When to use**:
- Click to filter geofences/tasks
- Use locked when you only care about your areas
- Use unlocked to see company-wide overview

**How it works**:

**Locked Mode** (assigned only):
```
Map shows:
✓ Only geofences YOU are assigned to
✓ Your tasks only
✗ Other teams' geofences hidden
✗ Other teams' tasks hidden

Button icon: 🔒 (lock)
Tooltip: "Show all geofences"
```

**Unlocked Mode** (all geofences):
```
Map shows:
✓ ALL geofences in system
✓ ALL tasks in system
✓ Other teams' areas visible
✓ Everything visible

Button icon: 🔓 (unlock)
Tooltip: "Show assigned only"
```

**Result**:
```
Click button → Filter toggles → More/fewer items shown
```

---

## QUICK REFERENCE TABLE

| Button | Icon | Function | Toggle? | When to Use |
|--------|------|----------|---------|------------|
| **1** | 🎯 | Center map on you | No | Location stuck or scrolled away |
| **2** | 📍 | Switch geofences ↔ tasks | Yes | View different data types |
| **3** | 🔒 | Show assigned ↔ all | Yes | Filter by visibility |

---

## COMMON SCENARIOS

### Scenario 1: "Where am I?"
1. Click Button 1 (Center) → Map centers on you
2. Check if blue or red pin
3. Blue = Inside geofence ✓
4. Red = Outside geofence ✗

### Scenario 2: "Show me my work area"
1. Click Button 2 (Toggle) → Switch to Geofence View
2. Click Button 3 (Toggle) → Lock to assigned only
3. See only YOUR geofences with boundaries

### Scenario 3: "Show me all tasks in the system"
1. Click Button 2 (Toggle) → Switch to Task View
2. Click Button 3 (Toggle) → Unlock to see all
3. See all task markers on map

### Scenario 4: "I want overview of all work areas"
1. Click Button 3 (Toggle) → Unlock (public)
2. See all geofences in company
3. Useful for admins or planning

---

## TIPS & TRICKS

### 💡 Tip 1: Pin Locations Mean Status
- **Blue pin** = You are INSIDE a geofence ✓
- **Red pin** = You are OUTSIDE all geofences ✗
- Check alert message at top of map

### 💡 Tip 2: Use Tooltips
- Hover over buttons to see tooltip
- Tooltip explains current action
- Helps if you forget button purpose

### 💡 Tip 3: Toggle Combinations
- Geofence View + Assigned Filter = Your work area
- Task View + All Filter = Company tasks
- Play with combinations to find useful view

### 💡 Tip 4: Center After Moving
- If location not updating, click Center button
- Refreshes GPS position
- Updates geofence status

---

## VISUAL MAP INDICATORS

### Geofence View:
```
      Geofence Circle
    ╱───────────────╲
   │   [Blue Pin]   │
   │      (You)     │
    ╲───────────────╱
   Geofence Name
   "Sales Area"
   Radius: 100m
```

### Task View:
```
      Task Marker
         (🔷)
        Status:
       In Progress
      
   [Blue Pin]
      (You)
```

### Status Indicators:
```
Alert: You are outside the geofence area (RED ❌)
       ↓ Means you're outside work boundary

No Alert (Normal state)
       ↓ Means you're inside work boundary or
         not viewing geofence mode
```

---

## TROUBLESHOOTING

| Problem | Solution |
|---------|----------|
| Can't see myself on map | Click Button 1 to center |
| Don't see any geofences | Check Button 3 - may be filtered |
| Don't see tasks | Check Button 2 - may be in geofence view |
| Location not updating | Click Button 1 to refresh |
| Confused which button is which | Hover for tooltip |

---

## SUMMARY

✅ **Button 1**: Keep map centered on your location  
✅ **Button 2**: Switch what you see (geofences vs tasks)  
✅ **Button 3**: Filter what you see (your area vs company)  

**Master these 3 buttons and the map becomes your best tool for navigation and task management!**

---

*Last Updated: November 24, 2025*
*Version: 2.1 - Enhanced with real-time tracking*
