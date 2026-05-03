class DashboardStats {
  final UserStats users;
  final GeofenceStats geofences;
  final TaskStats tasks;
  final AttendanceStats attendance;
  final RecentActivities recentActivities;

  DashboardStats({
    required this.users,
    required this.geofences,
    required this.tasks,
    required this.attendance,
    required this.recentActivities,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      users: UserStats.fromJson(json['users']),
      geofences: GeofenceStats.fromJson(json['geofences']),
      tasks: TaskStats.fromJson(json['tasks']),
      attendance: AttendanceStats.fromJson(json['attendance']),
      recentActivities: RecentActivities.fromJson(json['recentActivities']),
    );
  }
}

class UserStats {
  final int totalEmployees;
  final int activeEmployees;
  final int totalAdmins;
  final int inactiveEmployees;

  UserStats({
    required this.totalEmployees,
    required this.activeEmployees,
    required this.totalAdmins,
    required this.inactiveEmployees,
  });

  factory UserStats.fromJson(Map<String, dynamic> json) {
    return UserStats(
      totalEmployees: json['totalEmployees'] ?? 0,
      activeEmployees: json['activeEmployees'] ?? 0,
      totalAdmins: json['totalAdmins'] ?? 0,
      inactiveEmployees: json['inactiveEmployees'] ?? 0,
    );
  }
}

class GeofenceStats {
  final int total;
  final int active;
  final int inactive;

  GeofenceStats({
    required this.total,
    required this.active,
    required this.inactive,
  });

  factory GeofenceStats.fromJson(Map<String, dynamic> json) {
    return GeofenceStats(
      total: json['total'] ?? 0,
      active: json['active'] ?? 0,
      inactive: json['inactive'] ?? 0,
    );
  }
}

class TaskStats {
  final int total;
  final int pending;
  final int completed;
  final int inProgress;

  TaskStats({
    required this.total,
    required this.pending,
    required this.completed,
    required this.inProgress,
  });

  factory TaskStats.fromJson(Map<String, dynamic> json) {
    return TaskStats(
      total: json['total'] ?? 0,
      pending: json['pending'] ?? 0,
      completed: json['completed'] ?? 0,
      inProgress: json['inProgress'] ?? 0,
    );
  }
}

class AttendanceStats {
  final int today;
  final int todayCheckIns;
  final int todayCheckOuts;
  final List<AttendanceTrend> trends;

  AttendanceStats({
    required this.today,
    required this.todayCheckIns,
    required this.todayCheckOuts,
    required this.trends,
  });

  factory AttendanceStats.fromJson(Map<String, dynamic> json) {
    return AttendanceStats(
      today: json['today'] ?? 0,
      todayCheckIns: json['todayCheckIns'] ?? 0,
      todayCheckOuts: json['todayCheckOuts'] ?? 0,
      trends: (json['trends'] as List<dynamic>?)
          ?.map((e) => AttendanceTrend.fromJson(e))
          .toList() ?? [],
    );
  }
}

class AttendanceTrend {
  final String date;
  final int count;

  AttendanceTrend({
    required this.date,
    required this.count,
  });

  factory AttendanceTrend.fromJson(Map<String, dynamic> json) {
    return AttendanceTrend(
      date: json['date'] ?? '',
      count: json['count'] ?? 0,
    );
  }
}

class RecentActivities {
  final List<RecentAttendance> attendances;
  final List<RecentTask> tasks;

  RecentActivities({
    required this.attendances,
    required this.tasks,
  });

  factory RecentActivities.fromJson(Map<String, dynamic> json) {
    return RecentActivities(
      attendances: (json['attendances'] as List<dynamic>?)
          ?.map((e) => RecentAttendance.fromJson(e))
          .toList() ?? [],
      tasks: (json['tasks'] as List<dynamic>?)
          ?.map((e) => RecentTask.fromJson(e))
          .toList() ?? [],
    );
  }
}

class RecentAttendance {
  final String id;
  final String userName;
  final String userEmail;
  final String geofenceName;
  final DateTime timestamp;
  final String status;

  RecentAttendance({
    required this.id,
    required this.userName,
    required this.userEmail,
    required this.geofenceName,
    required this.timestamp,
    required this.status,
  });

  factory RecentAttendance.fromJson(Map<String, dynamic> json) {
    return RecentAttendance(
      id: json['_id'] ?? '',
      userName: json['user']?['name'] ?? '',
      userEmail: json['user']?['email'] ?? '',
      geofenceName: json['geofence']?['name'] ?? '',
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      status: json['status'] ?? '',
    );
  }
}

class RecentTask {
  final String id;
  final String title;
  final String description;
  final String status;
  final String? assignedToName;
  final String? assignedToEmail;
  final DateTime createdAt;

  RecentTask({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    this.assignedToName,
    this.assignedToEmail,
    required this.createdAt,
  });

  factory RecentTask.fromJson(Map<String, dynamic> json) {
    return RecentTask(
      id: json['_id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      status: json['status'] ?? '',
      assignedToName: json['assignedTo']?['name'],
      assignedToEmail: json['assignedTo']?['email'],
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
    );
  }
}

class RealtimeUpdates {
  final int onlineUsers;
  final List<RecentAttendance> recentCheckIns;
  final List<RecentTask> pendingTasksToday;
  final DateTime timestamp;

  RealtimeUpdates({
    required this.onlineUsers,
    required this.recentCheckIns,
    required this.pendingTasksToday,
    required this.timestamp,
  });

  factory RealtimeUpdates.fromJson(Map<String, dynamic> json) {
    return RealtimeUpdates(
      onlineUsers: json['onlineUsers'] ?? 0,
      recentCheckIns: (json['recentCheckIns'] as List<dynamic>?)
          ?.map((e) => RecentAttendance.fromJson(e))
          .toList() ?? [],
      pendingTasksToday: (json['pendingTasksToday'] as List<dynamic>?)
          ?.map((e) => RecentTask.fromJson(e))
          .toList() ?? [],
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }
}
