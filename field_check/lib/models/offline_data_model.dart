class OfflineData {
  final String id;
  final String dataType;
  final String dataJson;
  final DateTime createdAt;
  bool isSynced;

  OfflineData({
    required this.id,
    required this.dataType,
    required this.dataJson,
    required this.createdAt,
    this.isSynced = false,
  });

  factory OfflineData.fromJson(Map<String, dynamic> json) {
    return OfflineData(
      id: json['id'],
      dataType: json['dataType'],
      dataJson: json['dataJson'],
      createdAt: DateTime.parse(json['createdAt']),
      isSynced: json['isSynced'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'dataType': dataType,
      'dataJson': dataJson,
      'createdAt': createdAt.toIso8601String(),
      'isSynced': isSynced,
    };
  }

  OfflineData copyWith({
    String? id,
    String? dataType,
    String? dataJson,
    DateTime? createdAt,
    bool? isSynced,
  }) {
    return OfflineData(
      id: id ?? this.id,
      dataType: dataType ?? this.dataType,
      dataJson: dataJson ?? this.dataJson,
      createdAt: createdAt ?? this.createdAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}