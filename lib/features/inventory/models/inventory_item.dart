import 'package:flutter/material.dart';

/// Data tampilan satu unit aset individual dari koleksi `assets`.
///
/// CATATAN PEMELIHARAAN: `code` adalah barcode unit, sedangkan `itemId` dapat
/// dipakai bersama unit lain dengan nama/kategori sama. Kondisi dan lokasi
/// tetap milik masing-masing aset, bukan data induk barang.
class InventoryItem {
  const InventoryItem({
    this.assetId,
    this.itemId,
    this.kindId,
    this.categoryId,
    required this.code,
    required this.name,
    required this.category,
    required this.locationId,
    required this.location,
    required this.condition,
    required this.icon,
    required this.color,
  });

  factory InventoryItem.fromServer({
    required String assetId,
    required String itemId,
    required String kindId,
    required String categoryId,
    required String code,
    required String name,
    required String category,
    required String locationId,
    required String location,
    required String condition,
  }) {
    final normalizedCategory = category.toLowerCase();
    final (icon, color) = normalizedCategory.contains('elektronik')
        ? (Icons.devices_other_rounded, const Color(0xFFE9F2FF))
        : normalizedCategory.contains('mebel')
        ? (Icons.chair_alt_rounded, const Color(0xFFFFF3E5))
        : normalizedCategory.contains('olahraga')
        ? (Icons.sports_basketball_rounded, const Color(0xFFFFEDE8))
        : (Icons.inventory_2_outlined, const Color(0xFFE7F7F1));
    return InventoryItem(
      assetId: assetId,
      itemId: itemId,
      kindId: kindId,
      categoryId: categoryId,
      code: code,
      name: name,
      category: category,
      locationId: locationId,
      location: location,
      condition: condition,
      icon: icon,
      color: color,
    );
  }

  final String? assetId;
  final String? itemId;
  final String? kindId;
  final String? categoryId;
  final String code;
  final String name;
  final String category;
  final String locationId;
  final String location;
  final String condition;
  final IconData icon;
  final Color color;

  InventoryItem copyWith({String? condition}) {
    return InventoryItem(
      code: code,
      assetId: assetId,
      itemId: itemId,
      kindId: kindId,
      categoryId: categoryId,
      name: name,
      category: category,
      locationId: locationId,
      location: location,
      condition: condition ?? this.condition,
      icon: icon,
      color: color,
    );
  }
}

/// Riwayat yang dipetakan dari koleksi `asset_events`.
class AssetConditionEvent {
  const AssetConditionEvent({
    this.eventType = 'condition_changed',
    required this.assetCode,
    required this.previousCondition,
    required this.newCondition,
    required this.performedBy,
    required this.notes,
    required this.occurredAt,
  });

  final String eventType;
  final String assetCode;
  final String previousCondition;
  final String newCondition;
  final String performedBy;
  final String notes;
  final DateTime occurredAt;
}

class InventorySnapshot {
  const InventorySnapshot({required this.items, required this.conditionEvents});

  final List<InventoryItem> items;
  final List<AssetConditionEvent> conditionEvents;
}
