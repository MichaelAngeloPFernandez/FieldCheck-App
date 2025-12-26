# FieldCheck UML Diagrams - Quick Start Guide

## 🚀 Get Started in 5 Minutes

### Step 1: View Diagrams Online (Easiest)
1. Go to: https://www.plantuml.com/plantuml/uml/
2. Copy content from any `.puml` file
3. Paste into the editor
4. Click "Submit"
5. View the rendered diagram

### Step 2: View in VS Code (Recommended)
1. Install "PlantUML" extension by jebbs
2. Open any `.puml` file
3. Press `Alt+D` to preview
4. Export as PNG/SVG/PDF if needed

### Step 3: Generate Images (For Presentations)
```bash
# Install PlantUML
npm install -g plantuml

# Generate PNG
plantuml 01_USE_CASE_DIAGRAM.puml

# Generate SVG
plantuml -tsvg 01_USE_CASE_DIAGRAM.puml
```

---

## 📚 Which Diagram Should I Read?

### "I want to understand the system"
→ Read: **04_SYSTEM_ARCHITECTURE.puml**

### "I want to understand how check-in works"
→ Read: **03_SEQUENCE_CHECKIN.puml**

### "I want to understand the database"
→ Read: **05_ENTITY_RELATIONSHIP_DIAGRAM.puml**

### "I want to understand user workflows"
→ Read: **17_INTERACTION_OVERVIEW.puml**

### "I want to understand all features"
→ Read: **01_USE_CASE_DIAGRAM.puml**

### "I want to understand the code structure"
→ Read: **09_COMPONENT_DIAGRAM.puml**

### "I want to understand how tasks work"
→ Read: **11_SEQUENCE_TASK_ASSIGNMENT.puml** and **16_STATE_DIAGRAM_TASK_LIFECYCLE.puml**

### "I want to understand offline functionality"
→ Read: **12_TIMING_OFFLINE_SYNC.puml**

### "I want to understand GPS validation"
→ Read: **10_GEOFENCE_VALIDATION_FLOWCHART.puml**

### "I want to understand report generation"
→ Read: **15_ACTIVITY_REPORT_GENERATION.puml**

### "I want to understand deployment"
→ Read: **08_DEPLOYMENT_DIAGRAM.puml**

---

## 📊 All 17 Diagrams at a Glance

| # | Name | Type | File |
|---|------|------|------|
| 1 | Use Case | Behavioral | `01_USE_CASE_DIAGRAM.puml` |
| 2 | Class | Structural | `02_CLASS_DIAGRAM.puml` |
| 3 | Sequence (Check-In) | Behavioral | `03_SEQUENCE_CHECKIN.puml` |
| 4 | System Architecture | Structural | `04_SYSTEM_ARCHITECTURE.puml` |
| 5 | Entity Relationship | Structural | `05_ENTITY_RELATIONSHIP_DIAGRAM.puml` |
| 6 | Data Flow | Behavioral | `06_DATA_FLOW_DIAGRAM.puml` |
| 7 | State (Attendance) | Behavioral | `07_STATE_DIAGRAM_ATTENDANCE.puml` |
| 8 | Deployment | Structural | `08_DEPLOYMENT_DIAGRAM.puml` |
| 9 | Component | Structural | `09_COMPONENT_DIAGRAM.puml` |
| 10 | Geofence Validation | Behavioral | `10_GEOFENCE_VALIDATION_FLOWCHART.puml` |
| 11 | Sequence (Task Assignment) | Behavioral | `11_SEQUENCE_TASK_ASSIGNMENT.puml` |
| 12 | Timing (Offline Sync) | Behavioral | `12_TIMING_OFFLINE_SYNC.puml` |
| 13 | Collaboration | Behavioral | `13_COLLABORATION_DIAGRAM.puml` |
| 14 | Package | Structural | `14_PACKAGE_DIAGRAM.puml` |
| 15 | Activity (Report Generation) | Behavioral | `15_ACTIVITY_REPORT_GENERATION.puml` |
| 16 | State (Task Lifecycle) | Behavioral | `16_STATE_DIAGRAM_TASK_LIFECYCLE.puml` |
| 17 | Interaction Overview | Behavioral | `17_INTERACTION_OVERVIEW.puml` |

---

## 🎯 By Role

### 👨‍💻 Developer
1. **04_SYSTEM_ARCHITECTURE.puml** - Understand the big picture
2. **02_CLASS_DIAGRAM.puml** - Understand data structures
3. **09_COMPONENT_DIAGRAM.puml** - Understand code organization
4. **03_SEQUENCE_CHECKIN.puml** - Understand workflows

### 🗄️ Database Admin
1. **05_ENTITY_RELATIONSHIP_DIAGRAM.puml** - Database schema
2. **02_CLASS_DIAGRAM.puml** - Data model
3. **06_DATA_FLOW_DIAGRAM.puml** - Data flow

### 🚀 DevOps
1. **08_DEPLOYMENT_DIAGRAM.puml** - Deployment architecture
2. **04_SYSTEM_ARCHITECTURE.puml** - System overview
3. **09_COMPONENT_DIAGRAM.puml** - Components

### 📊 Project Manager
1. **17_INTERACTION_OVERVIEW.puml** - Daily workflows
2. **01_USE_CASE_DIAGRAM.puml** - Features
3. **04_SYSTEM_ARCHITECTURE.puml** - Overview

### 🎓 Student/Researcher
1. **01_USE_CASE_DIAGRAM.puml** - Features
2. **04_SYSTEM_ARCHITECTURE.puml** - Architecture
3. **02_CLASS_DIAGRAM.puml** - Design
4. **05_ENTITY_RELATIONSHIP_DIAGRAM.puml** - Database
5. All others for comprehensive understanding

---

## 🔑 Key Concepts

### Geofencing
- Circular boundary around job site
- Validated using Haversine formula
- Distance = 2R × arcsin(√(...))
- See: **10_GEOFENCE_VALIDATION_FLOWCHART.puml**

### Attendance States
- NotCheckedIn → CheckingIn → CheckedIn → CheckingOut → CheckedOut
- See: **07_STATE_DIAGRAM_ATTENDANCE.puml**

### Task States
- Pending → Assigned → InProgress → Completed
- Can be archived/restored
- See: **16_STATE_DIAGRAM_TASK_LIFECYCLE.puml**

### Offline Sync
- Save data locally when offline
- Auto-sync when online
- See: **12_TIMING_OFFLINE_SYNC.puml**

### Real-Time Updates
- Socket.io broadcasts events
- Admin dashboard updates instantly
- See: **04_SYSTEM_ARCHITECTURE.puml**

---

## 💻 Technology Stack

### Frontend
- **Flutter** - Mobile app framework
- **Flutter Map** - Mapping with OpenStreetMap
- **Provider** - State management
- **Geolocator** - GPS location
- **Socket IO Client** - Real-time updates

### Backend
- **Node.js** - Runtime
- **Express.js** - Web framework
- **MongoDB** - Database
- **Socket.io** - Real-time communication
- **JWT** - Authentication

---

## 🔐 Security Features

1. **JWT Authentication** - Secure tokens
2. **Password Hashing** - bcryptjs
3. **HTTPS/TLS** - Encrypted transmission
4. **Role-Based Access Control** - Admin vs Employee
5. **Data Encryption** - At rest and in transit

---

## 📈 System Capabilities

### Employee Features
✅ Secure login with JWT
✅ GPS-based check-in/check-out
✅ View assigned tasks
✅ Complete tasks
✅ View attendance history
✅ Offline data caching
✅ Automatic sync

### Admin Features
✅ Create and manage geofences
✅ Assign tasks to employees
✅ Real-time employee monitoring
✅ Generate attendance reports
✅ Generate task reports
✅ Export to PDF/Excel
✅ Archive/restore records

### System Features
✅ GPS validation (Haversine formula)
✅ Offline synchronization
✅ Real-time updates (Socket.io)
✅ Role-based access control
✅ Data encryption
✅ Audit logging

---

## 🎨 Diagram Symbols

### Actors
- Stick figures represent people (Employee, Admin)

### Use Cases
- Ovals represent actions/features

### Classes
- Rectangles with compartments for attributes and methods

### Entities
- Rectangles with attributes and primary keys

### States
- Rounded rectangles represent states

### Activities
- Rounded rectangles for actions
- Diamonds for decisions

### Components
- Rectangles with component icon

### Packages
- Folders/rectangles containing other elements

---

## 🔗 Related Files

- **README.md** - Detailed documentation
- **DIAGRAM_INDEX.md** - Complete index with descriptions
- **Capstone Paper** - Original research document
- **Source Code** - Implementation in `/backend` and `/field_check`

---

## 📞 Need Help?

1. **View a diagram online**: https://www.plantuml.com/plantuml/uml/
2. **Read the README**: Open `README.md`
3. **Check the index**: Open `DIAGRAM_INDEX.md`
4. **Review the paper**: Check capstone project document
5. **Check the code**: Look at implementation

---

## ✅ Checklist for Using Diagrams

- [ ] Read README.md for overview
- [ ] View 04_SYSTEM_ARCHITECTURE.puml for big picture
- [ ] View 01_USE_CASE_DIAGRAM.puml for features
- [ ] View relevant diagrams for your role
- [ ] Export diagrams for presentations
- [ ] Share with team members
- [ ] Reference in documentation
- [ ] Keep updated with code changes

---

## 🚀 Next Steps

1. **View the diagrams** using PlantUML online editor
2. **Read README.md** for detailed explanations
3. **Check DIAGRAM_INDEX.md** for complete reference
4. **Review the capstone paper** for context
5. **Explore the source code** for implementation

---

**Happy Learning! 🎓**

For questions or suggestions, refer to the comprehensive documentation in this directory.
