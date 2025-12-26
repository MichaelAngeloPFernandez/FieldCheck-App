# FieldCheck UML Diagrams and Documentation

This directory contains comprehensive UML diagrams and flowcharts for the FieldCheck Mobile Geofenced Attendance Verification App, based on the capstone project paper.

## Overview

FieldCheck is a mobile application that uses GPS technology and geofencing to verify employee attendance at authorized work locations. This documentation provides visual representations of the system architecture, data flow, and key processes.

## Diagram Files

### 1. **01_USE_CASE_DIAGRAM.puml**
- **Purpose**: Shows all actors (Employee, Administrator, System) and their interactions with the system
- **Key Elements**:
  - Employee use cases: Check-in, Check-out, View tasks, View history
  - Admin use cases: Manage geofences, Assign tasks, Generate reports
  - System use cases: Validate GPS, Sync offline data, Send real-time updates
- **Use When**: Understanding user roles and system capabilities

### 2. **02_CLASS_DIAGRAM.puml**
- **Purpose**: Detailed object-oriented design showing all classes, attributes, and relationships
- **Key Classes**:
  - `User`: Employee and Administrator profiles
  - `Geofence`: Job site boundaries
  - `Attendance`: Check-in/out records
  - `Task`: Work assignments
  - `Report`: Generated reports
  - Services: Business logic layer
  - Controllers: API endpoints
- **Use When**: Understanding data structure and class relationships

### 3. **03_SEQUENCE_CHECKIN.puml**
- **Purpose**: Detailed step-by-step flow of the check-in process
- **Scenarios**:
  - Online check-in with GPS validation
  - Offline check-in with local storage
  - Automatic sync when connectivity returns
- **Key Interactions**:
  - Mobile app → Location Service → Backend API
  - Geofence validation using Haversine formula
  - Real-time updates via Socket.io
- **Use When**: Understanding the check-in workflow

### 4. **04_SYSTEM_ARCHITECTURE.puml**
- **Purpose**: High-level system architecture showing all layers and components
- **Layers**:
  - Client Layer: Flutter mobile app
  - Communication Layer: HTTP/REST and WebSocket
  - Backend Layer: Express.js server
  - Data Layer: MongoDB database
  - Security Layer: JWT, encryption, RBAC
- **Use When**: Understanding system structure and deployment

### 5. **05_ENTITY_RELATIONSHIP_DIAGRAM.puml**
- **Purpose**: Database schema showing all collections and relationships
- **Collections**:
  - Users
  - Geofences
  - Attendance
  - Tasks
  - Reports
  - Locations
  - UserTasks (many-to-many)
  - AuditLog
- **Use When**: Understanding database design

### 6. **06_DATA_FLOW_DIAGRAM.puml**
- **Purpose**: Shows data movement through the system
- **Levels**:
  - Level 0: Context diagram (high-level overview)
  - Level 1: Main processes and data stores
- **Key Processes**:
  - Authentication
  - Location Processing
  - Attendance Management
  - Task Management
  - Report Generation
  - Real-Time Updates
  - Offline Synchronization
- **Use When**: Tracing data flow through the system

### 7. **07_STATE_DIAGRAM_ATTENDANCE.puml**
- **Purpose**: Shows all possible states of an attendance record
- **States**:
  - NotCheckedIn
  - CheckingIn (validating location)
  - CheckedIn (active shift)
  - CheckingOut (validating location)
  - CheckedOut (shift complete)
  - OfflineMode (no internet)
- **Transitions**: Shows how states change based on user actions and system conditions
- **Use When**: Understanding attendance lifecycle

### 8. **08_DEPLOYMENT_DIAGRAM.puml**
- **Purpose**: Shows physical deployment of system components
- **Deployment Targets**:
  - Employee mobile devices (Android/iOS)
  - Admin mobile devices
  - Organization server (self-hosted or cloud)
  - Database server
  - External services (OpenStreetMap)
- **Use When**: Planning infrastructure and deployment

### 9. **09_COMPONENT_DIAGRAM.puml**
- **Purpose**: Shows all software components and their dependencies
- **Mobile Components**:
  - Presentation Layer (screens and widgets)
  - Business Logic Layer (managers and services)
  - Data Layer (local storage and cache)
  - Communication Layer (HTTP and WebSocket)
  - Device Integration (GPS, connectivity)
- **Backend Components**:
  - API Layer (routes)
  - Service Layer (business logic)
  - Middleware Layer (authentication, validation)
  - Real-Time Layer (Socket.io)
  - Data Access Layer (repositories)
  - Utility Layer (helpers)
- **Use When**: Understanding component structure

### 10. **10_GEOFENCE_VALIDATION_FLOWCHART.puml**
- **Purpose**: Detailed algorithm for validating if employee is within geofence
- **Algorithm**:
  - Get employee GPS coordinates
  - Retrieve all active geofences
  - Calculate distance using Haversine formula
  - Check if distance ≤ geofence radius
  - Create attendance record if valid
  - Handle offline mode if needed
- **Key Formula**: 
  ```
  d = 2R × arcsin(√(sin²((lat2-lat1)/2) + cos(lat1) × cos(lat2) × sin²((lon2-lon1)/2)))
  ```
- **Use When**: Understanding GPS validation logic

### 11. **11_SEQUENCE_TASK_ASSIGNMENT.puml**
- **Purpose**: Detailed flow of admin assigning task to employee
- **Steps**:
  - Admin creates task with details
  - Backend stores task and creates assignment
  - Socket.io broadcasts event to all clients
  - Employee receives notification
  - Employee sees task in their task list
- **Use When**: Understanding task assignment workflow

### 12. **12_TIMING_OFFLINE_SYNC.puml**
- **Purpose**: Shows timing of offline synchronization process
- **Scenario**:
  - Employee checks in while online
  - Moves to area with no signal
  - Checks out offline (saved locally)
  - Moves back to area with signal
  - Data automatically syncs
- **Use When**: Understanding offline functionality

### 13. **13_COLLABORATION_DIAGRAM.puml**
- **Purpose**: Shows object interactions for check-in process
- **Objects**:
  - Employee (actor)
  - Mobile App
  - GPS Service
  - Geofence Service
  - Attendance Service
  - Database
  - Socket.io
  - Admin Dashboard
- **Use When**: Understanding object collaboration

### 14. **14_PACKAGE_DIAGRAM.puml**
- **Purpose**: Shows package structure and dependencies
- **Packages**:
  - Mobile App (Presentation, Business Logic, Data, Communication, Device Integration)
  - Backend (API, Service, Middleware, Real-Time, Data Access, Utilities, Models)
  - Database
  - External Services
- **Use When**: Understanding code organization

### 15. **15_ACTIVITY_REPORT_GENERATION.puml**
- **Purpose**: Shows steps for generating and exporting reports
- **Process**:
  - Select report type (Attendance/Task/Archive)
  - Apply filters (date range, employees, geofences)
  - Query database and aggregate data
  - Format report with statistics
  - Export to PDF or Excel
  - Save or share file
- **Use When**: Understanding report generation workflow

## How to View These Diagrams

### Option 1: Online PlantUML Editor
1. Visit: https://www.plantuml.com/plantuml/uml/
2. Copy the contents of any `.puml` file
3. Paste into the editor
4. View the rendered diagram

### Option 2: VS Code Extension
1. Install "PlantUML" extension by jebbs
2. Open any `.puml` file
3. Press `Alt+D` to preview
4. Export as PNG, SVG, or PDF

### Option 3: Command Line
```bash
# Install PlantUML
npm install -g plantuml

# Generate PNG
plantuml 01_USE_CASE_DIAGRAM.puml

# Generate SVG
plantuml -tsvg 01_USE_CASE_DIAGRAM.puml
```

### Option 4: GitHub
- GitHub automatically renders PlantUML diagrams in markdown files
- Create a markdown file with:
  ```markdown
  ![Diagram](01_USE_CASE_DIAGRAM.puml)
  ```

## Key Concepts from the Paper

### Geofencing
- **Definition**: Imaginary boundary around a physical location using GPS coordinates
- **Implementation**: Circular geofences using Haversine formula
- **Future**: Polygon geofences using Ray Casting algorithm

### Authentication
- **Method**: JWT (JSON Web Tokens)
- **Access Token**: Expires after 1 hour
- **Refresh Token**: Expires after 7 days
- **Password**: Hashed using bcryptjs

### Offline Synchronization
- **Process**: Save data locally when offline, sync when online
- **Storage**: SharedPreferences on mobile device
- **Trigger**: Automatic detection of connectivity change

### Real-Time Updates
- **Technology**: Socket.io
- **Use Case**: Admin dashboard shows live employee locations
- **Benefit**: No need to refresh page for updates

### Role-Based Access Control (RBAC)
- **Admin Role**: Full access to all features
- **Employee Role**: Limited to own data and assigned tasks

## Technology Stack

### Frontend
- **Framework**: Flutter 3.9.0
- **Mapping**: Flutter Map 8.2.2 with OpenStreetMap
- **State Management**: Provider 6.0.0
- **Location**: Geolocator 14.0.2
- **Real-Time**: Socket IO Client 3.1.2
- **Storage**: Shared Preferences 2.2.2

### Backend
- **Runtime**: Node.js 16+
- **Framework**: Express.js
- **Database**: MongoDB 4.4+
- **Real-Time**: Socket.io 4.0+
- **Authentication**: JWT (jsonwebtoken)
- **Password**: bcryptjs
- **Export**: PDFKit, ExcelJS

## System Requirements

### Mobile Device
- Android 10+ or iOS 14+
- 2GB+ RAM
- 100MB+ storage
- GPS sensor
- Battery: 15-20% per 8-hour shift

### Server
- 4+ CPU cores
- 8GB+ RAM
- 250GB+ SSD
- Ubuntu Server 20.04+ or Windows Server 2019+
- Stable internet (10Mbps+)

## Key Algorithms

### Haversine Formula
Calculates distance between two GPS points:
```
d = 2R × arcsin(√(sin²((lat2-lat1)/2) + cos(lat1) × cos(lat2) × sin²((lon2-lon1)/2)))
```
- R = Earth's radius (6,371 km)
- Used for circular geofence validation

### Ray Casting Algorithm
Determines if point is inside polygon (future enhancement):
1. Draw ray from point to infinity
2. Count polygon edge crossings
3. Odd count = inside, Even count = outside

## Security Features

1. **JWT Authentication**: Secure token-based authentication
2. **Password Hashing**: bcryptjs for secure password storage
3. **HTTPS/TLS**: Encrypted data transmission
4. **RBAC**: Role-based access control
5. **Data Encryption**: Sensitive data encrypted at rest and in transit
6. **Audit Logging**: Track all user actions

## Future Enhancements

1. **Polygon Geofences**: Support complex boundary shapes
2. **Bluetooth Beacons**: Improved indoor accuracy
3. **Facial Recognition**: Biometric verification
4. **Two-Factor Authentication**: Enhanced security
5. **Mobile Analytics**: Detailed usage statistics
6. **Integration APIs**: Connect with other systems

## Document References

This documentation is based on the FieldCheck capstone project paper:
- **Title**: FieldCheck: Mobile Geofenced Attendance Verification App for Field-Based Workers
- **Institution**: New Era University, College of Informatics and Computing Studies
- **Date**: February 2025
- **Authors**: Fernandez, Michael Angelo; Perfecto, Mark Karevin D.; Songco, Carl; Maquiling, Patrick

## Support

For questions about these diagrams:
1. Review the corresponding section in the capstone paper
2. Check the code implementation in the repository
3. Refer to the inline comments in the `.puml` files

---

**Last Updated**: December 2025
**Version**: 1.0
