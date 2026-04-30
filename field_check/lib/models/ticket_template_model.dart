class TicketTemplateModel {
  final String id;
  final String companyId;
  final String? companyName;
  final String? companyCode;
  final String name;
  final String description;
  final Map<String, dynamic> jsonSchema;
  final Map<String, dynamic>? workflow;
  final int? slaSeconds;
  final String visibility;
  final int version;
  final bool isActive;
  final String? createdBy;
  final DateTime? createdAt;

  TicketTemplateModel({
    required this.id,
    required this.companyId,
    this.companyName,
    this.companyCode,
    required this.name,
    this.description = '',
    required this.jsonSchema,
    this.workflow,
    this.slaSeconds,
    this.visibility = 'company',
    this.version = 1,
    this.isActive = true,
    this.createdBy,
    this.createdAt,
  });

  factory TicketTemplateModel.fromJson(Map<String, dynamic> json) {
    final company = json['company'];
    String companyId = '';
    String? companyName;
    String? companyCode;
    if (company is Map<String, dynamic>) {
      companyId = company['_id']?.toString() ?? '';
      companyName = company['name']?.toString();
      companyCode = company['code']?.toString();
    } else if (company is String) {
      companyId = company;
    }

    return TicketTemplateModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      companyId: companyId,
      companyName: companyName,
      companyCode: companyCode,
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      jsonSchema: json['json_schema'] is Map<String, dynamic>
          ? json['json_schema'] as Map<String, dynamic>
          : <String, dynamic>{},
      workflow: json['workflow'] is Map<String, dynamic>
          ? json['workflow'] as Map<String, dynamic>
          : null,
      slaSeconds: json['sla_seconds'] is num
          ? (json['sla_seconds'] as num).toInt()
          : null,
      visibility: json['visibility']?.toString() ?? 'company',
      version: json['version'] is num ? (json['version'] as num).toInt() : 1,
      isActive: json['isActive'] == true,
      createdBy: json['created_by'] is Map
          ? (json['created_by'] as Map)['name']?.toString()
          : json['created_by']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }

  /// Get the list of required fields from the JSON schema.
  List<String> get requiredFields {
    final req = jsonSchema['required'];
    if (req is List) return req.map((e) => e.toString()).toList();
    return [];
  }

  /// Get properties from the JSON schema.
  Map<String, dynamic> get properties {
    final props = jsonSchema['properties'];
    if (props is Map<String, dynamic>) return props;
    return {};
  }

  /// Format SLA as a human-readable duration.
  String? get slaFormatted {
    if (slaSeconds == null || slaSeconds == 0) return null;
    final hours = slaSeconds! ~/ 3600;
    final minutes = (slaSeconds! % 3600) ~/ 60;
    if (hours > 0 && minutes > 0) return '${hours}h ${minutes}m';
    if (hours > 0) return '${hours}h';
    return '${minutes}m';
  }
}
