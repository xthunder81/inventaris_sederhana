/// Barang dengan saldo per lokasi; berbeda dari aset yang dilacak per barcode.
///
/// CATATAN PEMELIHARAAN: total dihitung dari balances per lokasi agar daftar
/// tidak menyimpan saldo turunan yang bisa berbeda dari dokumen Mongo.
class StockItem {
  const StockItem({
    required this.itemId,
    required this.code,
    required this.name,
    required this.kindId,
    required this.categoryId,
    required this.category,
    required this.unit,
    required this.minimumStock,
    required this.balances,
  });

  final String itemId;
  final String code;
  final String name;
  final String kindId;
  final String categoryId;
  final String category;
  final String unit;
  final double minimumStock;
  final List<StockBalance> balances;

  double get total =>
      balances.fold<double>(0, (sum, row) => sum + row.quantity);
  bool get belowMinimum => total < minimumStock;
}

class StockBalance {
  const StockBalance({
    required this.locationId,
    required this.location,
    required this.quantity,
  });

  final String locationId;
  final String location;
  final double quantity;
}

class StockItemInput {
  const StockItemInput({
    required this.name,
    required this.kindId,
    required this.categoryId,
    required this.unit,
    required this.minimumStock,
    required this.locationId,
    required this.initialQuantity,
  });

  final String name;
  final String kindId;
  final String categoryId;
  final String unit;
  final double minimumStock;
  final String locationId;
  final double initialQuantity;
}

class StockItemEditInput {
  const StockItemEditInput({
    required this.itemId,
    required this.name,
    required this.categoryId,
    required this.unit,
    required this.minimumStock,
    required this.locationId,
    required this.quantity,
    required this.notes,
  });

  final String itemId;
  final String name;
  final String categoryId;
  final String unit;
  final double minimumStock;
  final String locationId;
  final double quantity;
  final String notes;
}
