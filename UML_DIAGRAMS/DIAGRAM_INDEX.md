# FieldCheck UML Diagrams - Complete Index

## 📋 Quick Reference

| # | Diagram | Type | Purpose | Best For |
|---|---------|------|---------|----------|
| 1 | Use Case | Behavioral | System actors and interactions | Understanding user roles |
| 2 | Class | Structural | Object-oriented design | Data structure & relationships |
| 3 | Sequence (Check-In) | Behavioral | Step-by-step check-in flow | Understanding workflows |
| 4 | System Architecture | Structural | High-level system design | System overview |
| 5 | Entity Relationship | Structural | Database schema | Database design |
| 6 | Data Flow | Behavioral | Data movement through system | Tracing data flow |
| 7 | State (Attendance) | Behavioral | Attendance record states | Understanding state transitions |
| 8 | Deployment | Structural | Physical deployment | Infrastructure planning |
| 9 | Component | Structural | Software components | Code organization |
| 10 | Geofence Validation | Behavioral | GPS validation algorithm | Algorithm understanding |
| 11 | Sequence (Task Assignment) | Behavioral | Task assignment flow | Task workflow |
| 12 | Timing (Offline Sync) | Behavioral | Offline sync timing | Offline functionality |
| 13 | Collaboration | Behavioral | Object interactions | Object collaboration |
| 14 | Package | Structural | Package structure | Code organization |
| 15 | Activity (Report Generation) | Behavioral | Report generation process | Report workflow |
| 16 | State (Task Lifecycle) | Behavioral | Task state transitions | Task lifecycle |
| 17 | Interaction Overview | Behavioral | Daily workflows | System usage patterns |

---

## 📊 Diagrams by Category

### Structural Diagrams (System Design)
- **02_CLASS_DIAGRAM.puml** - Complete object model
- **04_SYSTEM_ARCHITECTURE.puml** - Layered architecture
- **05_ENTITY_RELATIONSHIP_DIAGRAM.puml** - Database schema
- **08_DEPLOYMENT_DIAGRAM.puml** - Physical deployment
- **09_COMPONENT_DIAGRAM.puml** - Software components
- **14_PACKAGE_DIAGRAM.puml** - Package organization

### Behavioral Diagrams (System Behavior)
- **01_USE_CASE_DIAGRAM.puml** - User interactions
- **03_SEQUENCE_CHECKIN.puml** - Check-in workflow
- **06_DATA_FLOW_DIAGRAM.puml** - Data movement
- **07_STATE_DIAGRAM_ATTENDANCE.puml** - Attendance states
- **10_GEOFENCE_VALIDATION_FLOWCHART.puml** - GPS validation
- **11_SEQUENCE_TASK_ASSIGNMENT.puml** - Task assignment
- **12_TIMING_OFFLINE_SYNC.puml** - Offline sync timing
- **13_COLLABORATION_DIAGRAM.puml** - Object interactions
- **15_ACTIVITY_REPORT_GENERATION.puml** - Report generation
- **16_STATE_DIAGRAM_TASK_LIFECYCLE.puml** - Task states
- **17_INTERACTION_OVERVIEW.puml** - Daily workflows

---

## 🎯 Diagrams by Use Case

### For Understanding the System
1. Start with: **04_SYSTEM_ARCHITECTURE.puml**
2. Then: **01_USE_CASE_DIAGRAM.puml**
3. Then: **14_PACKAGE_DIAGRAM.puml**

### For Understanding Employee Workflow
1. **17_INTERACTION_OVERVIEW.puml** - Daily workflow
2. **03_SEQUENCE_CHECKIN.puml** - Check-in process
3. **07_STATE_DIAGRAM_ATTENDANCE.puml** - Attendance states
4. **12_TIMING_OFFLINE_SYNC.puml** - Offline handling

### For Understanding Admin Workflow
1. **17_INTERACTION_OVERVIEW.puml** - Daily workflow
2. **11_SEQUENCE_TASK_ASSIGNMENT.puml** - Task assignment
3. **15_ACTIVITY_REPORT_GENERATION.puml** - Report generation
4. **16_STATE_DIAGRAM_TASK_LIFECYCLE.puml** - Task states

### For Understanding Data
1. **05_ENTITY_RELATIONSHIP_DIAGRAM.puml** - Database schema
2. **02_CLASS_DIAGRAM.puml** - Object model
3. **06_DATA_FLOW_DIAGRAM.puml** - Data flow

### For Understanding Technology
1. **04_SYSTEM_ARCHITECTURE.puml** - Tech stack
2. **08_DEPLOYMENT_DIAGRAM.puml** - Deployment
3. **09_COMPONENT_DIAGRAM.puml** - Components

### For Understanding Algorithms
1. **10_GEOFENCE_VALIDATION_FLOWCHART.puml** - GPS validation
2. **12_TIMING_OFFLINE_SYNC.puml** - Sync algorithm
3. **15_ACTIVITY_REPORT_GENERATION.puml** - Report generation

---

## 📖 Detailed Diagram Descriptions

### 1️⃣ USE CASE DIAGRAM (01_USE_CASE_DIAGRAM.puml)
**What it shows**: All actors and their interactions with the system

**Key Elements**:
- **Actors**: Employee, Administrator, System
- **Employee Use Cases**: Login, Check-In, Check-Out, View Tasks, View History, View Profile
- **Admin Use Cases**: Create/Edit/Delete Geofences, Assign Tasks, Manage Employees, Generate Reports, Export Data, Archive/Restore
- **System Use Cases**: Validate GPS, Sync Offline Data, Send Real-Time Updates

**When to use**: 
- Explaining system capabilities to stakeholders
- Understanding user roles and permissions
- Identifying all system features

---

### 2️⃣ CLASS DIAGRAM (02_CLASS_DIAGRAM.puml)
**What it shows**: Complete object-oriented design with all classes and relationships

**Key Classes**:
- **User**: Employee and admin profiles with authentication
- **Geofence**: Job site boundaries with validation methods
- **Attendance**: Check-in/out records with duration calculation
- **Task**: Work assignments with status tracking
- **Report**: Generated reports with export functionality
- **Location**: GPS coordinates with geofence validation
- **Services**: Business logic for each domain
- **Controllers**: API endpoints

**When to use**:
- Understanding data structure
- Implementing backend services
- Database design
- API design

---

### 3️⃣ SEQUENCE DIAGRAM - CHECK-IN (03_SEQUENCE_CHECKIN.puml)
**What it shows**: Step-by-step flow of employee check-in process

**Scenarios**:
1. **Online Check-In**:
   - Get GPS location
   - Send to backend
   - Validate against geofences
   - Create attendance record
   - Broadcast via Socket.io
   - Show confirmation

2. **Offline Check-In**:
   - Get GPS location
   - Save to local storage
   - Show "Saved Offline" message
   - Monitor connectivity
   - Auto-sync when online

**When to use**:
- Understanding check-in workflow
- Debugging check-in issues
- Explaining process to developers
- Testing scenarios

---

### 4️⃣ SYSTEM ARCHITECTURE (04_SYSTEM_ARCHITECTURE.puml)
**What it shows**: High-level system architecture with all layers

**Layers**:
1. **Client Layer**: Flutter mobile app with UI and local storage
2. **Communication Layer**: HTTP/REST and WebSocket with encryption
3. **Backend Layer**: Express.js server with routes and business logic
4. **Data Layer**: MongoDB with collections
5. **Security Layer**: JWT, encryption, RBAC
6. **External Services**: OpenStreetMap, file export

**When to use**:
- System overview presentations
- Infrastructure planning
- Technology stack discussion
- Deployment planning

---

### 5️⃣ ENTITY RELATIONSHIP DIAGRAM (05_ENTITY_RELATIONSHIP_DIAGRAM.puml)
**What it shows**: Database schema with all collections and relationships

**Collections**:
- **Users**: Employee and admin profiles
- **Geofences**: Job site boundaries
- **Attendance**: Check-in/out records
- **Tasks**: Work assignments
- **Reports**: Generated reports
- **Locations**: GPS coordinates
- **UserTasks**: Many-to-many task assignments
- **AuditLog**: Activity tracking

**Relationships**:
- User 1:N Attendance (makes)
- User 1:N Task (creates)
- User 1:N Report (generates)
- Geofence 1:N Attendance (contains)
- Geofence 1:N Task (has)
- Task 1:N UserTask (assigned_in)

**When to use**:
- Database design
- MongoDB schema planning
- Query optimization
- Data integrity

---

### 6️⃣ DATA FLOW DIAGRAM (06_DATA_FLOW_DIAGRAM.puml)
**What it shows**: How data moves through the system

**Levels**:
- **Level 0**: Context diagram (high-level overview)
- **Level 1**: Main processes and data stores

**Main Processes**:
1. Authentication - Verify user identity
2. Location Processing - Validate GPS coordinates
3. Attendance Management - Create/update attendance
4. Task Management - Assign and track tasks
5. Report Generation - Create reports
6. Real-Time Updates - Broadcast events
7. Offline Sync - Synchronize offline data

**When to use**:
- Tracing data flow
- Understanding process interactions
- Identifying data dependencies
- System analysis

---

### 7️⃣ STATE DIAGRAM - ATTENDANCE (07_STATE_DIAGRAM_ATTENDANCE.puml)
**What it shows**: All possible states of an attendance record

**States**:
1. **NotCheckedIn**: Employee not at job site
2. **CheckingIn**: Validating GPS location
3. **CheckedIn**: Employee working
4. **CheckingOut**: Validating check-out location
5. **CheckedOut**: Shift complete
6. **OfflineMode**: No internet connection

**Transitions**:
- Valid location → Check-in recorded
- Invalid location → Error message
- Internet lost → Offline mode
- Internet restored → Auto-sync

**When to use**:
- Understanding attendance lifecycle
- Handling state transitions
- Error scenarios
- Testing state changes

---

### 8️⃣ DEPLOYMENT DIAGRAM (08_DEPLOYMENT_DIAGRAM.puml)
**What it shows**: Physical deployment of system components

**Deployment Nodes**:
1. **Employee Mobile Device**: Flutter app with GPS
2. **Admin Mobile Device**: Flutter app with dashboard
3. **Organization Server**: Express.js backend
4. **Database Server**: MongoDB
5. **External Services**: OpenStreetMap, file export

**Connections**:
- Mobile ↔ Server: HTTPS/TLS
- Mobile ↔ Server: WebSocket (Socket.io)
- Server ↔ Database: MongoDB protocol
- Server ↔ External: API calls

**When to use**:
- Infrastructure planning
- Deployment strategy
- Network architecture
- System requirements

---

### 9️⃣ COMPONENT DIAGRAM (09_COMPONENT_DIAGRAM.puml)
**What it shows**: All software components and dependencies

**Mobile Components**:
- Presentation Layer (screens, widgets)
- Business Logic Layer (managers, services)
- Data Layer (storage, cache)
- Communication Layer (HTTP, WebSocket)
- Device Integration (GPS, connectivity)

**Backend Components**:
- API Layer (routes)
- Service Layer (business logic)
- Middleware Layer (auth, validation)
- Real-Time Layer (Socket.io)
- Data Access Layer (repositories)
- Utility Layer (helpers)

**When to use**:
- Code organization
- Component dependencies
- Architecture planning
- Refactoring decisions

---

### 🔟 GEOFENCE VALIDATION FLOWCHART (10_GEOFENCE_VALIDATION_FLOWCHART.puml)
**What it shows**: Detailed GPS validation algorithm

**Algorithm Steps**:
1. Get employee GPS coordinates
2. Retrieve all active geofences
3. For each geofence:
   - Calculate distance using Haversine formula
   - Check if distance ≤ radius
4. If valid geofence found:
   - Create attendance record
   - Send to backend or save offline
5. If no valid geofence:
   - Show error message

**Haversine Formula**:
```
d = 2R × arcsin(√(sin²((lat2-lat1)/2) + cos(lat1) × cos(lat2) × sin²((lon2-lon1)/2)))
```

**When to use**:
- Understanding GPS validation
- Implementing geofence logic
- Debugging location issues
- Algorithm optimization

---

### 1️⃣1️⃣ SEQUENCE DIAGRAM - TASK ASSIGNMENT (11_SEQUENCE_TASK_ASSIGNMENT.puml)
**What it shows**: Step-by-step flow of admin assigning task to employee

**Steps**:
1. Admin creates task with details
2. Backend validates and stores
3. Creates UserTask assignment
4. Emits Socket.io event
5. Broadcasts to all connected clients
6. Employee receives notification
7. Employee sees task in list

**When to use**:
- Understanding task workflow
- Debugging task issues
- Explaining to stakeholders
- Testing task assignment

---

### 1️⃣2️⃣ TIMING DIAGRAM - OFFLINE SYNC (12_TIMING_OFFLINE_SYNC.puml)
**What it shows**: Timing of offline synchronization

**Scenario**:
1. Employee checks in (online)
2. Moves to area with no signal
3. Checks out (offline, saved locally)
4. Moves back to area with signal
5. Data automatically syncs
6. Confirmation received

**When to use**:
- Understanding offline functionality
- Testing sync scenarios
- Explaining to users
- Debugging sync issues

---

### 1️⃣3️⃣ COLLABORATION DIAGRAM (13_COLLABORATION_DIAGRAM.puml)
**What it shows**: Object interactions for check-in process

**Objects**:
- Employee (actor)
- Mobile App
- GPS Service
- Geofence Service
- Attendance Service
- Database
- Socket.io
- Admin Dashboard

**Interactions**:
- Numbered messages showing sequence
- Alternative paths for valid/invalid location

**When to use**:
- Understanding object collaboration
- Debugging interactions
- Design review
- Testing scenarios

---

### 1️⃣4️⃣ PACKAGE DIAGRAM (14_PACKAGE_DIAGRAM.puml)
**What it shows**: Package structure and dependencies

**Mobile App Packages**:
- Presentation (screens, widgets)
- Business Logic (managers, services)
- Data (storage, models)
- Communication (HTTP, WebSocket)
- Device Integration (GPS, connectivity)

**Backend Packages**:
- API Layer (routes)
- Service Layer (services)
- Middleware (auth, validation)
- Real-Time (Socket.io)
- Data Access (repositories)
- Utilities (helpers)
- Models (data models)

**When to use**:
- Code organization
- Architecture planning
- Dependency management
- Refactoring

---

### 1️⃣5️⃣ ACTIVITY DIAGRAM - REPORT GENERATION (15_ACTIVITY_REPORT_GENERATION.puml)
**What it shows**: Steps for generating and exporting reports

**Process**:
1. Select report type (Attendance/Task/Archive)
2. Apply filters (date range, employees, geofences)
3. Query database
4. Aggregate data
5. Format report
6. Export to PDF or Excel
7. Save or share file

**When to use**:
- Understanding report workflow
- Testing report generation
- Explaining to users
- Debugging report issues

---

### 1️⃣6️⃣ STATE DIAGRAM - TASK LIFECYCLE (16_STATE_DIAGRAM_TASK_LIFECYCLE.puml)
**What it shows**: All possible states of a task

**States**:
1. **Pending**: Created, waiting for assignment
2. **Assigned**: Assigned to employee
3. **In Progress**: Employee working on task
4. **Completed**: Task finished
5. **Archived**: Task archived
6. **Restored**: Task restored from archive

**Transitions**:
- Pending → Assigned (admin assigns)
- Assigned → In Progress (employee starts)
- In Progress → Completed (employee finishes)
- Any state → Archived (admin archives)
- Archived → Restored (admin restores)

**When to use**:
- Understanding task lifecycle
- Handling state transitions
- Archive/restore functionality
- Testing task states

---

### 1️⃣7️⃣ INTERACTION OVERVIEW (17_INTERACTION_OVERVIEW.puml)
**What it shows**: Daily workflows and system interactions

**Employee Workflow**:
- Morning: Open app, authenticate, view tasks
- At site: Check-in, view geofence tasks
- During shift: Complete tasks, update status
- End of shift: Check-out, shift complete

**Admin Workflow**:
- Morning: Open app, check dashboard
- During day: Monitor locations, assign tasks
- End of day: Generate reports, archive records

**System Processes**:
- Connectivity monitoring
- Real-time updates
- Data validation
- Report generation

**When to use**:
- System overview
- User training
- Workflow documentation
- Process improvement

---

## 🔄 Recommended Reading Order

### For New Developers
1. 04_SYSTEM_ARCHITECTURE.puml - Understand overall structure
2. 01_USE_CASE_DIAGRAM.puml - Understand features
3. 02_CLASS_DIAGRAM.puml - Understand data model
4. 09_COMPONENT_DIAGRAM.puml - Understand components
5. 03_SEQUENCE_CHECKIN.puml - Understand workflows

### For Database Designers
1. 05_ENTITY_RELATIONSHIP_DIAGRAM.puml - Database schema
2. 02_CLASS_DIAGRAM.puml - Object model
3. 06_DATA_FLOW_DIAGRAM.puml - Data flow

### For Frontend Developers
1. 01_USE_CASE_DIAGRAM.puml - Features
2. 17_INTERACTION_OVERVIEW.puml - User workflows
3. 03_SEQUENCE_CHECKIN.puml - Check-in flow
4. 11_SEQUENCE_TASK_ASSIGNMENT.puml - Task flow
5. 15_ACTIVITY_REPORT_GENERATION.puml - Report flow

### For Backend Developers
1. 04_SYSTEM_ARCHITECTURE.puml - Architecture
2. 02_CLASS_DIAGRAM.puml - Data model
3. 09_COMPONENT_DIAGRAM.puml - Components
4. 06_DATA_FLOW_DIAGRAM.puml - Data flow
5. 10_GEOFENCE_VALIDATION_FLOWCHART.puml - Algorithms

### For DevOps/Infrastructure
1. 08_DEPLOYMENT_DIAGRAM.puml - Deployment
2. 04_SYSTEM_ARCHITECTURE.puml - Architecture
3. 05_ENTITY_RELATIONSHIP_DIAGRAM.puml - Database

### For Project Managers
1. 17_INTERACTION_OVERVIEW.puml - Daily workflows
2. 01_USE_CASE_DIAGRAM.puml - Features
3. 04_SYSTEM_ARCHITECTURE.puml - Overview

---

## 💡 Tips for Using These Diagrams

### Viewing
- Use PlantUML online editor: https://www.plantuml.com/plantuml/uml/
- Install VS Code extension for live preview
- Export to PNG, SVG, or PDF for presentations

### Modifying
- Edit `.puml` files in any text editor
- Update diagrams as system evolves
- Keep diagrams in sync with code

### Sharing
- Include in documentation
- Use in presentations
- Reference in code comments
- Share with stakeholders

### Best Practices
- Keep diagrams up-to-date
- Use consistent naming
- Add comments for clarity
- Reference specific sections
- Link to related diagrams

---

## 📞 Support & Questions

For questions about specific diagrams:
1. Check the README.md file
2. Review the capstone paper
3. Check the code implementation
4. Refer to inline comments in `.puml` files

---

**Last Updated**: December 2025
**Total Diagrams**: 17
**Format**: PlantUML (.puml)
**Status**: Complete and Ready for Use
