enum MaintenanceStatus { reported, inProgress, completed, cancelled }

/// CATATAN PEMELIHARAAN: field catatan mengikuti `maintenance_records` pada
/// database/mongo/init.js. `assetId` adalah referensi unit aset yang disimpan;
/// kode/nama aset dan nama pelapor diisi dari data master oleh backend.
class MaintenanceRecord {
  const MaintenanceRecord({
    required this.id,
    required this.assetId,
    required this.assetCode,
    required this.assetName,
    required this.reportedBy,
    required this.status,
    required this.description,
    required this.cost,
    required this.reportedAt,
    this.closedAt,
  });

  final String id;
  final String assetId;
  final String assetCode;
  final String assetName;
  final String reportedBy;
  final MaintenanceStatus status;
  final String description;
  final double cost;
  final DateTime reportedAt;
  final DateTime? closedAt;

  MaintenanceRecord copyWith({
    MaintenanceStatus? status,
    double? cost,
    DateTime? closedAt,
  }) {
    return MaintenanceRecord(
      id: id,
      assetId: assetId,
      assetCode: assetCode,
      assetName: assetName,
      reportedBy: reportedBy,
      status: status ?? this.status,
      description: description,
      cost: cost ?? this.cost,
      reportedAt: reportedAt,
      closedAt: closedAt ?? this.closedAt,
    );
  }
}

String maintenanceStatusLabel(MaintenanceStatus status) => switch (status) {
  MaintenanceStatus.reported => 'Dilaporkan',
  MaintenanceStatus.inProgress => 'Sedang dikerjakan',
  MaintenanceStatus.completed => 'Selesai',
  MaintenanceStatus.cancelled => 'Dibatalkan',
};
