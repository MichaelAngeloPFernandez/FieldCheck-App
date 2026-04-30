class TicketModel {
  final String id;
  final String ticketNo;
  final String companyId;
  final String? companyName;
  final String? companyCode;
  final String templateId;
  final String? templateName;
  final int templateVersion;
  final Map<String, dynamic> data;
  final String status;
  final String? assigneeId;
  final String? assigneeName;
  final String? createdById;
  final String? createdByName;
  final List<String> attachments;
  final DateTime? slaDeadline;
  final String? slaStatus;
  final double? gpsLat;
  final double? gpsLng;
  final String? geofenceName;
  final String notes;
  final bool isArchived;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  TicketModel({
    required this.id,
    required this.ticketNo,
    required this.companyId,
    this.companyName,
    this.companyCode,
    required this.templateId,
    this.templateName,
    this.templateVersion = 1,
    required this.data,
    this.status = 'open',
    this.assigneeId,
    this.assigneeName,
    this.createdById,
    this.createdByName,
    this.attachments = const [],
    this.slaDeadline,
    this.slaStatus,
    this.gpsLat,
    this.gpsLng,
    this.geofenceName,
    this.notes = '',
    this.isArchived = false,
    this.completedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory TicketModel.fromJson(Map<String, dynamic> json) {
    // Parse company
    final company = json['company'];
    String companyId = '';
    String? companyName, companyCode;
    if (company is Map<String, dynamic>) {
      companyId = company['_id']?.toString() ?? '';
      companyName = company['name']?.toString();
      companyCode = company['code']?.toString();
    } else {
      companyId = company?.toString() ?? '';
    }

    // Parse template
    final template = json['template'];
    String templateId = '';
    String? templateName;
    if (template is Map<String, dynamic>) {
      templateId = template['_id']?.toString() ?? '';
      templateName = template['name']?.toString();
    } else {
      templateId = template?.toString() ?? '';
    }

    // Parse assignee
    final assignee = json['assignee'];
    String? assigneeId, assigneeName;
    if (assignee is Map<String, dynamic>) {
      assigneeId = assignee['_id']?.toString();
      assigneeName = assignee['name']?.toString();
    } else if (assignee is String) {
      assigneeId = assignee;
    }

    // Parse created_by
    final createdBy = json['created_by'];
    String? createdById, createdByName;
    if (createdBy is Map<String, dynamic>) {
      createdById = createdBy['_id']?.toString();
      createdByName = createdBy['name']?.toString();
    } else if (createdBy is String) {
      createdById = createdBy;
    }

    // Parse GPS
    final gps = json['gps'];
    double? lat, lng;
    if (gps is Map<String, dynamic>) {
      lat = gps['lat'] is num ? (gps['lat'] as num).toDouble() : null;
      lng = gps['lng'] is num ? (gps['lng'] as num).toDouble() : null;
    }

    // Parse geofence
    final gf = json['geofence'];
    String? geofenceName;
    if (gf is Map<String, dynamic>) {
      geofenceName = gf['name']?.toString();
    }

    return TicketModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      ticketNo: json['ticket_no']?.toString() ?? '',
      companyId: companyId,
      companyName: companyName,
      companyCode: companyCode,
      templateId: templateId,
      templateName: templateName,
      templateVersion: json['template_version'] is num
          ? (json['template_version'] as num).toInt()
          : 1,
      data: json['data'] is Map<String, dynamic>
          ? json['data'] as Map<String, dynamic>
          : <String, dynamic>{},
      status: json['status']?.toString() ?? 'open',
      assigneeId: assigneeId,
      assigneeName: assigneeName,
      createdById: createdById,
      createdByName: createdByName,
      attachments: (json['attachments'] is List)
          ? (json['attachments'] as List).map((e) => e.toString()).toList()
          : [],
      slaDeadline: json['sla_deadline'] != null
          ? DateTime.tryParse(json['sla_deadline'].toString())
          : null,
      slaStatus: json['sla_status']?.toString(),
      gpsLat: lat,
      gpsLng: lng,
      geofenceName: geofenceName,
      notes: json['notes']?.toString() ?? '',
      isArchived: json['isArchived'] == true,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'].toString())
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
    );
  }

  bool get isOverdue =>
      slaStatus == 'overdue' ||
      (slaDeadline != null && DateTime.now().isAfter(slaDeadline!));

  bool get isAtRisk => slaStatus == 'at_risk';
}
