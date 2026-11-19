enum MovementType { receipt, issue, transfer, adjustment }

enum MovementStatus { draft, posted, cancelled }

/// Header transaksi mutasi beserta detail barang per baris.
///
/// CATATAN PEMELIHARAAN: pertahankan mapping field dengan koleksi
/// `stock_movements` dan `stock_movement_lines` di `database/mongo/init.js`.
/// `itemId`/ID lokasi pada data demo perlu dipetakan ke ObjectId/string ID
/// database oleh repository; label nama hanya untuk tampilan.
class StockMovement {
  const StockMovement({
    required this.id,
    required this.movementNumber,
    required this.type,
    required this.status,
    required this.idempotencyKey,
    required this.performedBy,
    required this.createdAt,
    required this.lines,
    this.postedAt,
  });

  final String id;
  final String movementNumber;
  final MovementType type;
  final MovementStatus status;
  final String idempotencyKey;
  final String performedBy;
  final DateTime createdAt;
  final DateTime? postedAt;
  final List<StockMovementLine> lines;

  StockMovement copyWith({MovementStatus? status, DateTime? postedAt}) {
    return StockMovement(
      id: id,
      movementNumber: movementNumber,
      type: type,
      status: status ?? this.status,
      idempotencyKey: idempotencyKey,
      performedBy: performedBy,
      createdAt: createdAt,
      postedAt: postedAt ?? this.postedAt,
      lines: lines,
    );
  }
}

/// Satu item, kuantitas, lokasi sumber/tujuan, dan catatan transaksi.
class StockMovementLine {
  const StockMovementLine({
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.notes,
    this.fromLocationId,
    this.fromLocationName,
    this.toLocationId,
    this.toLocationName,
  });

  final String itemId;
  final String itemName;
  final double quantity;
  final String notes;
  final String? fromLocationId;
  final String? fromLocationName;
  final String? toLocationId;
  final String? toLocationName;
}

String movementTypeLabel(MovementType type) => switch (type) {
  MovementType.receipt => 'Penerimaan',
  MovementType.issue => 'Pengeluaran',
  MovementType.transfer => 'Pemindahan',
  MovementType.adjustment => 'Penyesuaian',
};

String movementStatusLabel(MovementStatus status) => switch (status) {
  MovementStatus.draft => 'Draft',
  MovementStatus.posted => 'Diposting',
  MovementStatus.cancelled => 'Dibatalkan',
};
