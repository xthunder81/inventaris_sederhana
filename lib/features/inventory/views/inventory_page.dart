import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../models/stock_item.dart';
import '../../master_data/models/master_data.dart';
import '../services/asset_label_printer.dart';
import 'stock_items_page.dart';

const _inventoryPageSize = 8;
// CATATAN PEMELIHARAAN: samakan pilihan ini dengan katalog `conditions` di
// database/mongo/init.js; filter dan dialog perubahan memakai daftar yang sama.
const _inventoryConditions = [
  'Bagus',
  'Perlu perbaikan',
  'Dalam service',
  'Rusak',
];

// CATATAN PEMELIHARAAN: halaman menerima snapshot server dan query dari parent
// agar pencarian header memakai sumber yang sama dengan dashboard. Filter
// lokal hanya mengubah tampilan. Pagination memakai 8 data setelah filter;
// sesuaikan tes jika batas ini diubah.
class InventoryPage extends StatefulWidget {
  const InventoryPage({
    super.key,
    required this.items,
    required this.conditionEvents,
    required this.searchQuery,
    required this.onAddItem,
    required this.onEditItem,
    required this.onArchiveItem,
    required this.onUpdateCondition,
    this.stockItems = const [],
    this.stockCategories = const [],
    this.stockKinds = const [],
    this.locations = const [],
    this.searchQueryForStock = '',
    this.onCreateStockItem,
    this.onEditStockItem,
    this.stockItemsLoading = false,
    this.stockItemsError,
    this.onRetryStockItems,
    this.canManageAssets = true,
    this.canPrintAssetLabels = true,
  });

  final List<InventoryItem> items;
  final List<AssetConditionEvent> conditionEvents;
  final String searchQuery;
  final VoidCallback onAddItem;
  final ValueChanged<InventoryItem> onEditItem;
  final ValueChanged<InventoryItem> onArchiveItem;
  final void Function(InventoryItem, AssetConditionEvent) onUpdateCondition;
  final bool canManageAssets;
  final bool canPrintAssetLabels;
  final List<StockItem> stockItems;
  final List<ItemCategory> stockCategories;
  final List<ItemKind> stockKinds;
  final List<MasterLocation> locations;
  final String searchQueryForStock;
  final ValueChanged<StockItemInput>? onCreateStockItem;
  final ValueChanged<StockItemEditInput>? onEditStockItem;
  final bool stockItemsLoading;
  final String? stockItemsError;
  final VoidCallback? onRetryStockItems;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  String _selectedCategory = 'Semua kategori';
  String _selectedCondition = 'Semua kondisi';
  int _currentPage = 0;
  bool _showStockItems = false;

  List<InventoryItem> get _filteredItems {
    final query = widget.searchQuery.trim().toLowerCase();
    return widget.items.where((item) {
      final matchesQuery =
          query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.code.toLowerCase().contains(query) ||
          item.category.toLowerCase().contains(query) ||
          item.location.toLowerCase().contains(query);
      final matchesCategory =
          _selectedCategory == 'Semua kategori' ||
          item.category == _selectedCategory;
      final matchesCondition =
          _selectedCondition == 'Semua kondisi' ||
          item.condition == _selectedCondition;
      return matchesQuery && matchesCategory && matchesCondition;
    }).toList();
  }

  @override
  void didUpdateWidget(covariant InventoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pencarian baru harus mulai dari awal; jika data/filter berkurang,
    // pastikan indeks halaman tidak menunjuk ke halaman yang sudah hilang.
    if (oldWidget.searchQuery != widget.searchQuery) _currentPage = 0;
    final pageCount =
        (_filteredItems.length + _inventoryPageSize - 1) ~/ _inventoryPageSize;
    if (pageCount == 0) {
      _currentPage = 0;
    } else if (_currentPage >= pageCount) {
      _currentPage = pageCount - 1;
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SegmentedButton<bool>(
        key: const Key('inventory-kind-tabs'),
        segments: const [
          ButtonSegment(
            value: false,
            label: Text('Aset Tetap'),
            icon: Icon(Icons.qr_code_2_rounded),
          ),
          ButtonSegment(
            value: true,
            label: Text('Barang Habis Pakai'),
            icon: Icon(Icons.inventory_2_outlined),
          ),
        ],
        selected: {_showStockItems},
        onSelectionChanged: (value) => setState(() {
          _showStockItems = value.first;
          _currentPage = 0;
        }),
      ),
      const SizedBox(height: 18),
      if (_showStockItems)
        StockItemsPage(
          items: widget.stockItems,
          locations: widget.locations,
          categories: widget.stockCategories,
          kinds: widget.stockKinds,
          searchQuery: widget.searchQueryForStock,
          canManage: widget.canManageAssets,
          onCreate: widget.onCreateStockItem ?? (_) {},
          onEdit: widget.onEditStockItem ?? (_) {},
          isLoading: widget.stockItemsLoading,
          loadError: widget.stockItemsError,
          onRetry: widget.onRetryStockItems,
        )
      else
        _buildAssetContent(context),
    ],
  );

  Widget _buildAssetContent(BuildContext context) {
    final categories =
        widget.items.map((item) => item.category).toSet().toList()..sort();
    final goodCount = widget.items
        .where((item) => item.condition == 'Bagus')
        .length;
    final attentionCount = widget.items.length - goodCount;
    final serviceCount = widget.items
        .where((item) => item.condition == 'Dalam service')
        .length;
    final damagedCount = widget.items
        .where((item) => item.condition == 'Rusak')
        .length;
    final filteredItems = _filteredItems;
    final pageCount =
        (filteredItems.length + _inventoryPageSize - 1) ~/ _inventoryPageSize;
    final firstIndex = _currentPage * _inventoryPageSize;
    // Tabel dan kartu mobile menggunakan potongan daftar yang sama.
    final visibleItems = filteredItems
        .skip(firstIndex)
        .take(_inventoryPageSize)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 650;
            final heading = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Inventaris',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  widget.canManageAssets
                      ? 'Kelola daftar barang dan pantau kondisi inventaris sekolah.'
                      : 'Lihat daftar barang dan kondisi inventaris sekolah.',
                ),
              ],
            );
            final addButton = FilledButton.icon(
              key: const Key('inventory-create-item'),
              onPressed: widget.onAddItem,
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('Tambah Barang'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF168B83),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading,
                  if (widget.canManageAssets) ...[
                    const SizedBox(height: 16),
                    addButton,
                  ],
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: heading),
                if (widget.canManageAssets) addButton,
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        const _AssetScopeNotice(),
        const SizedBox(height: 16),
        _InventoryMetrics(
          total: widget.items.length,
          good: goodCount,
          needsAttention: attentionCount,
          service: serviceCount,
          damaged: damagedCount,
        ),
        const SizedBox(height: 18),
        _InventoryList(
          items: visibleItems,
          totalItems: filteredItems.length,
          currentPage: _currentPage,
          pageCount: pageCount,
          firstIndex: firstIndex,
          categories: categories,
          selectedCategory: _selectedCategory,
          selectedCondition: _selectedCondition,
          onCategoryChanged: (value) => setState(() {
            _selectedCategory = value;
            _currentPage = 0;
          }),
          onConditionChanged: (value) => setState(() {
            _selectedCondition = value;
            _currentPage = 0;
          }),
          onPreviousPage: () => setState(() => _currentPage--),
          onNextPage: () => setState(() => _currentPage++),
          onViewDetails: (item) => _showDetails(context, item),
          onUpdateCondition: _openConditionDialog,
          onEditItem: widget.onEditItem,
          onArchiveItem: widget.onArchiveItem,
          onShowLabel: (item) => _showAssetLabel(item),
          canManageAssets: widget.canManageAssets,
        ),
      ],
    );
  }

  void _showAssetLabel(InventoryItem item) {
    showDialog<void>(
      context: context,
      builder: (context) => AssetLabelDialog(
        item: item,
        schoolName: schoolNameForAssetLocation(
          item.locationId,
          widget.locations,
        ),
        canPrint: widget.canPrintAssetLabels,
      ),
    );
  }

  Future<void> _openConditionDialog(InventoryItem item) async {
    final event = await showDialog<AssetConditionEvent>(
      context: context,
      builder: (context) => ConditionChangeDialog(item: item),
    );
    if (event != null && mounted) widget.onUpdateCondition(item, event);
  }

  void _showDetails(BuildContext context, InventoryItem item) {
    final events = widget.conditionEvents
        .where((event) => event.assetCode == item.code)
        .toList();
    showDialog<void>(
      context: context,
      builder: (context) => _ItemDetailsDialog(
        item: item,
        conditionEvents: events,
        canManageAssets: widget.canManageAssets,
        onUpdateCondition: () => _openConditionDialog(item),
        onShowLabel: () => _showAssetLabel(item),
      ),
    );
  }
}

class _AssetScopeNotice extends StatelessWidget {
  const _AssetScopeNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF7F6),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFD8ECE9)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF168B83), size: 19),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Data aset dimuat dari server dan setiap unit memiliki satu '
              'barcode. Pencatatan saldo stok massal belum termasuk dalam '
              'cakupan inventaris aset ini.',
              style: TextStyle(
                color: Color(0xFF426B67),
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryMetrics extends StatelessWidget {
  const _InventoryMetrics({
    required this.total,
    required this.good,
    required this.needsAttention,
    required this.service,
    required this.damaged,
  });

  final int total;
  final int good;
  final int needsAttention;
  final int service;
  final int damaged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1200
            ? 5
            : constraints.maxWidth >= 800
            ? 3
            : constraints.maxWidth >= 480
            ? 2
            : 1;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        final metrics = [
          _InventoryMetric(
            label: 'Total aset',
            value: total,
            icon: Icons.inventory_2_outlined,
            color: const Color(0xFF168B83),
            tint: const Color(0xFFE7F4F2),
          ),
          _InventoryMetric(
            label: 'Kondisi bagus',
            value: good,
            icon: Icons.check_circle_outline_rounded,
            color: const Color(0xFF42A786),
            tint: const Color(0xFFEAF6F0),
          ),
          _InventoryMetric(
            label: 'Perlu perhatian',
            value: needsAttention,
            icon: Icons.build_circle_outlined,
            color: const Color(0xFFE59B3F),
            tint: const Color(0xFFFFF3E4),
          ),
          _InventoryMetric(
            key: const Key('inventory-metric-service'),
            label: 'Service',
            value: service,
            icon: Icons.home_repair_service_outlined,
            color: const Color(0xFF5677C8),
            tint: const Color(0xFFEDF1FF),
          ),
          _InventoryMetric(
            key: const Key('inventory-metric-damaged'),
            label: 'Rusak',
            value: damaged,
            icon: Icons.warning_amber_rounded,
            color: const Color(0xFFD26355),
            tint: const Color(0xFFFFEEEB),
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: metrics
              .map((metric) => SizedBox(width: width, child: metric))
              .toList(),
        );
      },
    );
  }
}

class _InventoryMetric extends StatelessWidget {
  const _InventoryMetric({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.tint,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEDF0F4)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  value.toString(),
                  style: const TextStyle(
                    color: Color(0xFF172B4D),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryList extends StatelessWidget {
  const _InventoryList({
    required this.items,
    required this.totalItems,
    required this.currentPage,
    required this.pageCount,
    required this.firstIndex,
    required this.categories,
    required this.selectedCategory,
    required this.selectedCondition,
    required this.onCategoryChanged,
    required this.onConditionChanged,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onViewDetails,
    required this.onUpdateCondition,
    required this.onEditItem,
    required this.onArchiveItem,
    required this.onShowLabel,
    required this.canManageAssets,
  });

  final List<InventoryItem> items;
  final int totalItems;
  final int currentPage;
  final int pageCount;
  final int firstIndex;
  final List<String> categories;
  final String selectedCategory;
  final String selectedCondition;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onConditionChanged;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final ValueChanged<InventoryItem> onViewDetails;
  final ValueChanged<InventoryItem> onUpdateCondition;
  final ValueChanged<InventoryItem> onEditItem;
  final ValueChanged<InventoryItem> onArchiveItem;
  final ValueChanged<InventoryItem> onShowLabel;
  final bool canManageAssets;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDF0F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 700;
              final title = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daftar Barang',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$totalItems barang ditampilkan',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              );
              final filters = Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InventoryFilterDropdown(
                    key: const Key('inventory-category-filter'),
                    value: selectedCategory,
                    options: ['Semua kategori', ...categories],
                    onChanged: onCategoryChanged,
                  ),
                  _InventoryFilterDropdown(
                    key: const Key('inventory-condition-filter'),
                    value: selectedCondition,
                    options: ['Semua kondisi', ..._inventoryConditions],
                    onChanged: onConditionChanged,
                  ),
                ],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 14), filters],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  filters,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            const _EmptyInventory()
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 700) {
                  return Column(
                    children: items
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _InventoryCard(
                              item: item,
                              onViewDetails: () => onViewDetails(item),
                              onUpdateCondition: () => onUpdateCondition(item),
                              onEditItem: () => onEditItem(item),
                              onArchiveItem: () => onArchiveItem(item),
                              onShowLabel: () => onShowLabel(item),
                              canManageAssets: canManageAssets,
                            ),
                          ),
                        )
                        .toList(),
                  );
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                      ),
                      child: DataTable(
                        headingRowColor: const WidgetStatePropertyAll(
                          Color(0xFFF8FAFC),
                        ),
                        headingTextStyle: const TextStyle(
                          color: Color(0xFF8994A7),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                        dataTextStyle: const TextStyle(
                          color: Color(0xFF53627A),
                          fontSize: 11,
                        ),
                        columns: const [
                          DataColumn(label: Text('KODE')),
                          DataColumn(label: Text('NAMA BARANG')),
                          DataColumn(label: Text('KATEGORI')),
                          DataColumn(label: Text('LOKASI')),
                          DataColumn(label: Text('KONDISI')),
                          DataColumn(label: Text('DETAIL')),
                        ],
                        rows: items
                            .map(
                              (item) => DataRow(
                                cells: [
                                  DataCell(Text(item.code)),
                                  DataCell(_ItemName(item: item)),
                                  DataCell(Text(item.category)),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.location_on_outlined,
                                          size: 14,
                                          color: Color(0xFF9AA5B5),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(item.location),
                                      ],
                                    ),
                                  ),
                                  DataCell(_ConditionBadge(item.condition)),
                                  DataCell(
                                    _InventoryActions(
                                      item: item,
                                      onViewDetails: () => onViewDetails(item),
                                      onUpdateCondition: () =>
                                          onUpdateCondition(item),
                                      onEditItem: () => onEditItem(item),
                                      onArchiveItem: () => onArchiveItem(item),
                                      onShowLabel: () => onShowLabel(item),
                                      canManageAssets: canManageAssets,
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
          if (totalItems > _inventoryPageSize) ...[
            const SizedBox(height: 12),
            _InventoryPagination(
              currentPage: currentPage,
              pageCount: pageCount,
              firstIndex: firstIndex + 1,
              lastIndex: firstIndex + items.length,
              totalItems: totalItems,
              onPrevious: onPreviousPage,
              onNext: onNextPage,
            ),
          ],
        ],
      ),
    );
  }
}

/// Menunjukkan rentang data aktif; tombol dinonaktifkan pada batas halaman.
class _InventoryPagination extends StatelessWidget {
  const _InventoryPagination({
    required this.currentPage,
    required this.pageCount,
    required this.firstIndex,
    required this.lastIndex,
    required this.totalItems,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentPage;
  final int pageCount;
  final int firstIndex;
  final int lastIndex;
  final int totalItems;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Menampilkan $firstIndex–$lastIndex dari $totalItems barang',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        IconButton(
          key: const Key('inventory-page-previous'),
          tooltip: 'Halaman inventaris sebelumnya',
          onPressed: currentPage > 0 ? onPrevious : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text(
          '${currentPage + 1} / $pageCount',
          key: const Key('inventory-page-indicator'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        IconButton(
          key: const Key('inventory-page-next'),
          tooltip: 'Halaman inventaris berikutnya',
          onPressed: currentPage < pageCount - 1 ? onNext : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _InventoryFilterDropdown extends StatelessWidget {
  const _InventoryFilterDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFDDE3EC)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          borderRadius: BorderRadius.circular(12),
          style: const TextStyle(
            color: Color(0xFF53627A),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
          items: options
              .map(
                (option) =>
                    DropdownMenuItem(value: option, child: Text(option)),
              )
              .toList(),
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }
}

class _ItemName extends StatelessWidget {
  const _ItemName({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: item.color,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(item.icon, size: 17, color: const Color(0xFF54657C)),
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF172B4D),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _InventoryActions extends StatelessWidget {
  const _InventoryActions({
    required this.item,
    required this.onViewDetails,
    required this.onUpdateCondition,
    required this.onEditItem,
    required this.onArchiveItem,
    required this.onShowLabel,
    required this.canManageAssets,
  });

  final InventoryItem item;
  final VoidCallback onViewDetails;
  final VoidCallback onUpdateCondition;
  final VoidCallback onEditItem;
  final VoidCallback onArchiveItem;
  final VoidCallback onShowLabel;
  final bool canManageAssets;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Aksi ${item.name}',
      onSelected: (action) {
        if (action == 'details') onViewDetails();
        if (action == 'condition') onUpdateCondition();
        if (action == 'edit') onEditItem();
        if (action == 'archive') onArchiveItem();
        if (action == 'label') onShowLabel();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'details',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.open_in_new_rounded, size: 18),
            title: Text('Detail barang'),
          ),
        ),
        if (canManageAssets)
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.edit_rounded, size: 18),
              title: Text('Edit data aset'),
            ),
          ),
        if (canManageAssets)
          const PopupMenuItem(
            value: 'archive',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.archive_outlined, size: 18),
              title: Text('Nonaktifkan aset'),
            ),
          ),
        if (canManageAssets)
          const PopupMenuItem(
            value: 'condition',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.edit_note_rounded, size: 18),
              title: Text('Ubah kondisi'),
            ),
          ),
        const PopupMenuItem(
          value: 'label',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.qr_code_2_rounded, size: 18),
            title: Text('Lihat label barcode'),
          ),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.all(8),
        child: Icon(Icons.more_horiz_rounded, color: Color(0xFF8994A7)),
      ),
    );
  }
}

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({
    required this.item,
    required this.onViewDetails,
    required this.onUpdateCondition,
    required this.onEditItem,
    required this.onArchiveItem,
    required this.onShowLabel,
    required this.canManageAssets,
  });

  final InventoryItem item;
  final VoidCallback onViewDetails;
  final VoidCallback onUpdateCondition;
  final VoidCallback onEditItem;
  final VoidCallback onArchiveItem;
  final VoidCallback onShowLabel;
  final bool canManageAssets;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFDFE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDF0F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _ItemName(item: item)),
              _InventoryActions(
                item: item,
                onViewDetails: onViewDetails,
                onUpdateCondition: onUpdateCondition,
                onEditItem: onEditItem,
                onArchiveItem: onArchiveItem,
                onShowLabel: onShowLabel,
                canManageAssets: canManageAssets,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(item.code, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _InventoryTag(
                icon: Icons.category_outlined,
                label: item.category,
              ),
              _InventoryTag(
                icon: Icons.location_on_outlined,
                label: item.location,
              ),
              _ConditionBadge(item.condition),
            ],
          ),
        ],
      ),
    );
  }
}

class _InventoryTag extends StatelessWidget {
  const _InventoryTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: const Color(0xFF8994A7)),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ConditionBadge extends StatelessWidget {
  const _ConditionBadge(this.condition);

  final String condition;

  @override
  Widget build(BuildContext context) {
    final color = switch (condition) {
      'Bagus' => const Color(0xFF329476),
      'Perlu perbaikan' => const Color(0xFFC17A21),
      'Dalam service' => const Color(0xFF5677C8),
      _ => const Color(0xFFD26355),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        condition,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyInventory extends StatelessWidget {
  const _EmptyInventory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
      child: Center(
        child: Column(
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              size: 34,
              color: Color(0xFF9AA5B5),
            ),
            const SizedBox(height: 10),
            Text(
              'Barang tidak ditemukan',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text('Ubah kata kunci atau filter, lalu coba lagi.'),
          ],
        ),
      ),
    );
  }
}

class _ItemDetailsDialog extends StatelessWidget {
  const _ItemDetailsDialog({
    required this.item,
    required this.conditionEvents,
    required this.canManageAssets,
    required this.onUpdateCondition,
    required this.onShowLabel,
  });

  final InventoryItem item;
  final List<AssetConditionEvent> conditionEvents;
  final bool canManageAssets;
  final VoidCallback onUpdateCondition;
  final VoidCallback onShowLabel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(item.name),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailLine(label: 'Kode barang', value: item.code),
              _DetailLine(label: 'Kategori', value: item.category),
              _DetailLine(label: 'Lokasi', value: item.location),
              _DetailLine(label: 'Kondisi saat ini', value: item.condition),
              const SizedBox(height: 10),
              Text(
                'Riwayat perubahan kondisi',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              if (conditionEvents.isEmpty)
                const Text(
                  'Belum ada perubahan kondisi yang dicatat.',
                  key: Key('inventory-condition-history-empty'),
                  style: TextStyle(color: Color(0xFF8994A7), fontSize: 12),
                )
              else
                ...conditionEvents.map(
                  (event) => _ConditionHistoryEntry(event: event),
                ),
              const SizedBox(height: 12),
              const Text(
                'Riwayat kondisi diambil dari catatan server; aset baru selalu '
                'dibuat sebagai unit tersendiri, bukan penambahan saldo stok.',
                style: TextStyle(color: Color(0xFF8994A7), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
        OutlinedButton.icon(
          key: const Key('inventory-show-label-from-detail'),
          onPressed: () {
            Navigator.pop(context);
            onShowLabel();
          },
          icon: const Icon(Icons.qr_code_2_rounded, size: 18),
          label: const Text('Label barcode'),
        ),
        if (canManageAssets)
          FilledButton.icon(
            key: const Key('inventory-update-condition-from-detail'),
            onPressed: () {
              Navigator.pop(context);
              onUpdateCondition();
            },
            icon: const Icon(Icons.edit_note_rounded, size: 18),
            label: const Text('Ubah kondisi'),
          ),
      ],
    );
  }
}

class _ConditionHistoryEntry extends StatelessWidget {
  const _ConditionHistoryEntry({required this.event});

  final AssetConditionEvent event;

  @override
  Widget build(BuildContext context) {
    final time = event.occurredAt.toLocal();
    final timestamp =
        '${time.day.toString().padLeft(2, '0')}/'
        '${time.month.toString().padLeft(2, '0')}/${time.year} '
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';

    return Container(
      key: ValueKey(
        'inventory-condition-history-entry-${event.occurredAt.microsecondsSinceEpoch}',
      ),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEDF0F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.eventType == 'received'
                ? 'Aset didaftarkan dengan kondisi ${event.newCondition}'
                : '${event.previousCondition} menjadi ${event.newCondition}',
            style: const TextStyle(
              color: Color(0xFF263752),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$timestamp · ${event.performedBy}',
            style: const TextStyle(color: Color(0xFF8994A7), fontSize: 10),
          ),
          const SizedBox(height: 4),
          Text(event.notes, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// CATATAN PEMELIHARAAN: kode barcode tetap kode aset server, sedangkan PDF
/// memakai media label 80 × 42 mm. Dialog sistem memilih printer/media tujuan.
class AssetLabelDialog extends StatelessWidget {
  const AssetLabelDialog({
    super.key,
    required this.item,
    required this.schoolName,
    this.canPrint = true,
  });

  final InventoryItem item;
  final String schoolName;
  final bool canPrint;

  Future<void> _printLabel(BuildContext context) async {
    try {
      final printed = await printAssetLabel(item: item, schoolName: schoolName);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              printed
                  ? 'Label ${item.code} siap dicetak.'
                  : 'Pencetakan label dibatalkan.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Dialog cetak tidak dapat dibuka. Periksa pengaturan printer.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('asset-label-preview'),
      title: const Text('Pratinjau Label Aset'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFDDE3EC)),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0D172B4D),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      schoolName.toUpperCase(),
                      key: const Key('asset-label-school-name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF53627A),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.name,
                      key: const Key('asset-label-item-name'),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF172B4D),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    BarcodeWidget(
                      key: const Key('asset-label-barcode'),
                      barcode: Barcode.code128(),
                      data: item.code,
                      width: 300,
                      height: 76,
                      drawText: false,
                      errorBuilder: (context, error) => Text(
                        'Kode tidak dapat dijadikan barcode: $error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      item.code,
                      key: const Key('asset-label-code'),
                      style: const TextStyle(
                        color: Color(0xFF263752),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Aset sekolah · Code 128',
                      style: TextStyle(color: Color(0xFF8994A7), fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFFB77B27),
                    size: 17,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tombol cetak membuka dialog printer dengan PDF label '
                      '80 × 42 mm. Pilih printer label dan pastikan ukuran '
                      'media pada driver sesuai.',
                      style: TextStyle(
                        color: Color(0xFF795B32),
                        fontSize: 11,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('asset-label-close'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
        if (canPrint)
          FilledButton.icon(
            key: const Key('asset-label-print'),
            onPressed: () => _printLabel(context),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Cetak label'),
          ),
      ],
    );
  }
}

/// CATATAN PEMELIHARAAN: dialog membentuk perubahan untuk satu ID aset;
/// backend tetap memeriksa kondisi lama, status aset, serta catatan sebelum
/// menyimpan `condition_id` baru dan event audit.
class ConditionChangeDialog extends StatefulWidget {
  const ConditionChangeDialog({super.key, required this.item});

  final InventoryItem item;

  @override
  State<ConditionChangeDialog> createState() => _ConditionChangeDialogState();
}

class _ConditionChangeDialogState extends State<ConditionChangeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  late String _newCondition;

  @override
  void initState() {
    super.initState();
    _newCondition = widget.item.condition;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String? _validateCondition(String? value) {
    if (value == null || value == widget.item.condition) {
      return 'Pilih kondisi yang berbeda dari kondisi saat ini.';
    }
    return null;
  }

  String? _validateNotes(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Catatan perubahan wajib diisi.';
    }
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.pop(
      context,
      AssetConditionEvent(
        assetCode: widget.item.code,
        previousCondition: widget.item.condition,
        newCondition: _newCondition,
        performedBy: '',
        notes: _notesController.text.trim(),
        occurredAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ubah Kondisi Aset'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF7F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Mockup: hanya ${widget.item.name} (${widget.item.code}) '
                    'yang berubah. Catatan ini belum disimpan ke database.',
                    style: const TextStyle(
                      color: Color(0xFF426B67),
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _DetailLine(
                  label: 'Kondisi saat ini',
                  value: widget.item.condition,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('condition-change-value-input'),
                  initialValue: _newCondition,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Kondisi baru'),
                  items: _inventoryConditions
                      .map(
                        (condition) => DropdownMenuItem(
                          value: condition,
                          child: Text(condition),
                        ),
                      )
                      .toList(),
                  validator: _validateCondition,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _newCondition = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('condition-change-notes-input'),
                  controller: _notesController,
                  maxLength: 2000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Catatan/alasan perubahan',
                    alignLabelWithHint: true,
                  ),
                  validator: _validateNotes,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const Key('save-condition-change'),
          onPressed: _submit,
          child: const Text('Simpan kondisi'),
        ),
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          const Text(': '),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

/// Menemukan nama sekolah melalui rantai parent dari lokasi penyimpanan aset.
/// CATATAN PEMELIHARAAN: label memakai node bertipe `sekolah`, bukan ruang;
/// jika master induk tidak lengkap atau bersiklus, tampilkan penanda jelas.
String schoolNameForAssetLocation(
  String locationId,
  List<MasterLocation> locations,
) {
  final byId = {for (final location in locations) location.id: location};
  final visited = <String>{};
  var current = byId[locationId];
  while (current != null && visited.add(current.id)) {
    if (current.locationType.trim().toLowerCase() == 'sekolah') {
      final name = current.name.trim();
      if (name.isNotEmpty) return name;
      break;
    }
    final parentId = current.parentId;
    if (parentId == null || parentId.trim().isEmpty) break;
    current = byId[parentId];
  }
  return 'Nama sekolah belum diatur';
}
