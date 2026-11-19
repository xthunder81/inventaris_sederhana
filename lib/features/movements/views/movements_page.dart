// CATATAN PEMELIHARAAN: halaman ini menerima mutasi, barang, dan lokasi dari
// parent. Create/cancel menunggu hasil API sebelum state berubah; draft tidak
// mengubah saldo; posting memakai response server setelah transaksi atomik.
import 'dart:math';

import 'package:flutter/material.dart';

import '../../inventory/models/inventory_item.dart';
import '../../inventory/models/stock_item.dart';
import '../../master_data/models/master_data.dart';
import '../models/stock_movement.dart';

const _movementPageSize = 8;

class MovementsPage extends StatefulWidget {
  const MovementsPage({
    super.key,
    required this.movements,
    required this.items,
    this.stockItems = const [],
    required this.locations,
    required this.searchQuery,
    required this.onCreate,
    required this.onCancel,
    this.onPost,
    this.canManageMovements = true,
  });

  final List<StockMovement> movements;
  final List<InventoryItem> items;
  final List<StockItem> stockItems;
  final List<MasterLocation> locations;
  final String searchQuery;
  final Future<void> Function(StockMovement) onCreate;
  final Future<void> Function(StockMovement) onCancel;
  final Future<void> Function(StockMovement)? onPost;
  final bool canManageMovements;

  @override
  State<MovementsPage> createState() => _MovementsPageState();
}

class _MovementsPageState extends State<MovementsPage> {
  MovementType? _typeFilter;
  MovementStatus? _statusFilter;
  int _currentPage = 0;
  bool _isSaving = false;
  String? _cancellingMovementId;
  String? _postingMovementId;

  List<StockMovement> get _filteredMovements {
    final query = widget.searchQuery.trim().toLowerCase();
    return widget.movements.where((movement) {
      final matchesQuery =
          query.isEmpty ||
          movement.movementNumber.toLowerCase().contains(query) ||
          movementTypeLabel(movement.type).toLowerCase().contains(query) ||
          movementStatusLabel(movement.status).toLowerCase().contains(query) ||
          movement.lines.any(
            (line) =>
                line.itemName.toLowerCase().contains(query) ||
                (line.fromLocationName?.toLowerCase().contains(query) ??
                    false) ||
                (line.toLocationName?.toLowerCase().contains(query) ?? false),
          );
      final matchesType = _typeFilter == null || movement.type == _typeFilter;
      final matchesStatus =
          _statusFilter == null || movement.status == _statusFilter;
      return matchesQuery && matchesType && matchesStatus;
    }).toList();
  }

  @override
  void didUpdateWidget(covariant MovementsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) _currentPage = 0;
    final pageCount =
        (_filteredMovements.length + _movementPageSize - 1) ~/
        _movementPageSize;
    if (pageCount == 0) {
      _currentPage = 0;
    } else if (_currentPage >= pageCount) {
      _currentPage = pageCount - 1;
    }
  }

  Future<void> _openCreateDialog() async {
    final items = _availableItems;
    final activeLocations = widget.locations
        .where((location) => location.isActive)
        .toList();
    if (items.isEmpty || activeLocations.isEmpty || _isSaving) return;
    final result = await showDialog<StockMovement>(
      context: context,
      builder: (context) =>
          MovementDialog(items: items, locations: activeLocations),
    );
    if (result == null || !mounted) return;
    setState(() => _isSaving = true);
    try {
      await widget.onCreate(result);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  List<InventoryItem> get _availableItems {
    final unique = <String, InventoryItem>{};
    for (final item in widget.items) {
      final itemId = item.itemId;
      if (itemId != null) unique.putIfAbsent(itemId, () => item);
    }
    for (final item in widget.stockItems) {
      unique.putIfAbsent(
        item.itemId,
        () => InventoryItem(
          itemId: item.itemId,
          kindId: item.kindId,
          categoryId: item.categoryId,
          code: item.code,
          name: item.name,
          category: item.category,
          locationId: item.balances.isEmpty
              ? ''
              : item.balances.first.locationId,
          location: item.balances.isEmpty
              ? 'Belum ada saldo'
              : item.balances.first.location,
          condition: 'Stok',
          icon: Icons.inventory_2_outlined,
          color: const Color(0xFFE7F7F1),
        ),
      );
    }
    return unique.values.toList();
  }

  Future<void> _confirmCancel(StockMovement movement) async {
    if (_cancellingMovementId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan draft mutasi?'),
        content: Text(
          'Draft ${movement.movementNumber} akan ditandai dibatalkan. '
          'Stok tidak berubah karena draft belum diposting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            key: const Key('confirm-cancel-movement'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Batalkan draft'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cancellingMovementId = movement.id);
    try {
      await widget.onCancel(movement);
    } finally {
      if (mounted) setState(() => _cancellingMovementId = null);
    }
  }

  Future<void> _confirmPost(StockMovement movement) async {
    if (_postingMovementId != null || widget.onPost == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Posting mutasi?'),
        content: Text(
          'Mutasi ${movement.movementNumber} akan memperbarui saldo stok dan tidak dapat dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            key: const Key('confirm-post-movement'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Posting'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _postingMovementId = movement.id);
    try {
      await widget.onPost!(movement);
    } finally {
      if (mounted) setState(() => _postingMovementId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredMovements;
    final pageCount =
        (filtered.length + _movementPageSize - 1) ~/ _movementPageSize;
    final firstIndex = _currentPage * _movementPageSize;
    final visible = filtered.skip(firstIndex).take(_movementPageSize).toList();
    final draftCount = widget.movements
        .where((movement) => movement.status == MovementStatus.draft)
        .length;
    final postedCount = widget.movements
        .where((movement) => movement.status == MovementStatus.posted)
        .length;
    final cancelledCount = widget.movements
        .where((movement) => movement.status == MovementStatus.cancelled)
        .length;

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
                  'Mutasi Barang',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  widget.canManageMovements
                      ? 'Catat penerimaan, pengeluaran, pemindahan, dan penyesuaian stok.'
                      : 'Lihat riwayat penerimaan, pengeluaran, dan pemindahan stok.',
                ),
              ],
            );
            final createButton = FilledButton.icon(
              key: const Key('create-movement'),
              onPressed:
                  _availableItems.isEmpty ||
                      widget.locations
                          .where((location) => location.isActive)
                          .isEmpty ||
                      _isSaving
                  ? null
                  : _openCreateDialog,
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('Buat Mutasi'),
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
                  if (widget.canManageMovements) ...[
                    const SizedBox(height: 16),
                    createButton,
                  ],
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: heading),
                if (widget.canManageMovements) createButton,
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        const _MovementStatusNotice(),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MovementMetric(
              label: 'Total mutasi',
              value: widget.movements.length,
              icon: Icons.swap_horiz_rounded,
              color: const Color(0xFF5677C8),
            ),
            _MovementMetric(
              label: 'Draft',
              value: draftCount,
              icon: Icons.edit_note_rounded,
              color: const Color(0xFFE59B3F),
            ),
            _MovementMetric(
              label: 'Diposting',
              value: postedCount,
              icon: Icons.check_circle_outline_rounded,
              color: const Color(0xFF168B83),
            ),
            _MovementMetric(
              label: 'Dibatalkan',
              value: cancelledCount,
              icon: Icons.cancel_outlined,
              color: const Color(0xFF8994A7),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
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
                  final compact = constraints.maxWidth < 650;
                  final heading = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Riwayat Mutasi',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${filtered.length} mutasi ditampilkan',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  );
                  final filters = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MovementFilter<MovementType?>(
                        key: const Key('movement-type-filter'),
                        value: _typeFilter,
                        emptyLabel: 'Semua jenis',
                        options: [
                          const _FilterOption(null, 'Semua jenis'),
                          ...MovementType.values.map(
                            (type) =>
                                _FilterOption(type, movementTypeLabel(type)),
                          ),
                        ],
                        onChanged: (value) => setState(() {
                          _typeFilter = value;
                          _currentPage = 0;
                        }),
                      ),
                      _MovementFilter<MovementStatus?>(
                        key: const Key('movement-status-filter'),
                        value: _statusFilter,
                        emptyLabel: 'Semua status',
                        options: [
                          const _FilterOption(null, 'Semua status'),
                          ...MovementStatus.values.map(
                            (status) => _FilterOption(
                              status,
                              movementStatusLabel(status),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(() {
                          _statusFilter = value;
                          _currentPage = 0;
                        }),
                      ),
                    ],
                  );
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [heading, const SizedBox(height: 14), filters],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: heading),
                      filters,
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              if (filtered.isEmpty)
                _EmptyMovements(
                  hasAnyMovement: widget.movements.isNotEmpty,
                  onCreate: _openCreateDialog,
                  canCreate:
                      widget.canManageMovements &&
                      _availableItems.isNotEmpty &&
                      widget.locations.any((location) => location.isActive),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 740) {
                      return Column(
                        children: visible
                            .map(
                              (movement) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _MovementCard(
                                  movement: movement,
                                  onDetails: () =>
                                      _showMovementDetails(context, movement),
                                  onCancel:
                                      widget.canManageMovements &&
                                          movement.status ==
                                              MovementStatus.draft
                                      ? () => _confirmCancel(movement)
                                      : null,
                                  onPost:
                                      widget.canManageMovements &&
                                          movement.status ==
                                              MovementStatus.draft &&
                                          widget.onPost != null
                                      ? () => _confirmPost(movement)
                                      : null,
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
                            columns: const [
                              DataColumn(label: Text('NOMOR MUTASI')),
                              DataColumn(label: Text('JENIS')),
                              DataColumn(label: Text('BARANG')),
                              DataColumn(label: Text('JUMLAH')),
                              DataColumn(label: Text('TANGGAL')),
                              DataColumn(label: Text('STATUS')),
                              DataColumn(label: Text('AKSI')),
                            ],
                            rows: visible
                                .map(
                                  (movement) => DataRow(
                                    cells: [
                                      DataCell(
                                        Text(
                                          movement.movementNumber,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(movementTypeLabel(movement.type)),
                                      ),
                                      DataCell(
                                        Text(
                                          _itemsSummary(movement),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      DataCell(
                                        Text(_quantitySummary(movement)),
                                      ),
                                      DataCell(
                                        Text(_formatDate(movement.createdAt)),
                                      ),
                                      DataCell(
                                        _MovementStatusBadge(
                                          status: movement.status,
                                        ),
                                      ),
                                      DataCell(
                                        _MovementActions(
                                          movement: movement,
                                          onDetails: () => _showMovementDetails(
                                            context,
                                            movement,
                                          ),
                                          onCancel:
                                              widget.canManageMovements &&
                                                  movement.status ==
                                                      MovementStatus.draft
                                              ? () => _confirmCancel(movement)
                                              : null,
                                          onPost:
                                              widget.canManageMovements &&
                                                  movement.status ==
                                                      MovementStatus.draft &&
                                                  widget.onPost != null
                                              ? () => _confirmPost(movement)
                                              : null,
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
              if (filtered.length > _movementPageSize) ...[
                const SizedBox(height: 12),
                _MovementPagination(
                  currentPage: _currentPage,
                  pageCount: pageCount,
                  firstIndex: firstIndex + 1,
                  lastIndex: firstIndex + visible.length,
                  total: filtered.length,
                  onPrevious: () => setState(() => _currentPage--),
                  onNext: () => setState(() => _currentPage++),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Draft tersimpan melalui API, tetapi belum mengubah saldo. Posting dilakukan
/// dari daftar setelah petugas mengonfirmasi perubahan saldo yang permanen.
class MovementDialog extends StatefulWidget {
  const MovementDialog({
    super.key,
    required this.items,
    required this.locations,
  });

  final List<InventoryItem> items;
  final List<MasterLocation> locations;

  @override
  State<MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<MovementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController(text: '1');
  final _notesController = TextEditingController();
  late String _itemId;
  late String _fromLocationId;
  late String _toLocationId;
  MovementType _type = MovementType.transfer;

  @override
  void initState() {
    super.initState();
    _itemId = widget.items.first.itemId!;
    _fromLocationId = widget.locations.first.id;
    _toLocationId = widget.locations.length > 1
        ? widget.locations[1].id
        : widget.locations.first.id;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? _validateQuantity(String? value) {
    final quantity = double.tryParse(value?.trim() ?? '');
    if (quantity == null || !quantity.isFinite || quantity <= 0) {
      return 'Jumlah harus lebih besar dari 0';
    }
    return null;
  }

  String? _validateDestination(String? value) {
    if (value == null || value.isEmpty) return 'Pilih lokasi tujuan';
    if (_type == MovementType.transfer && value == _fromLocationId) {
      return 'Lokasi tujuan harus berbeda dari sumber';
    }
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now();
    final item = widget.items.firstWhere(
      (candidate) => candidate.itemId == _itemId,
    );
    final fromLocation = widget.locations
        .where((location) => location.id == _fromLocationId)
        .firstOrNull;
    final toLocation = widget.locations
        .where((location) => location.id == _toLocationId)
        .firstOrNull;

    final movementId = now.microsecondsSinceEpoch.toString();
    final idempotencyKey =
        'draft-${now.microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';
    final line = StockMovementLine(
      itemId: item.itemId!,
      itemName: item.name,
      quantity: double.parse(_quantityController.text.trim()),
      notes: _notesController.text.trim(),
      fromLocationId: switch (_type) {
        MovementType.issue || MovementType.transfer => fromLocation?.id,
        _ => null,
      },
      fromLocationName: switch (_type) {
        MovementType.issue || MovementType.transfer => fromLocation?.name,
        _ => null,
      },
      toLocationId: switch (_type) {
        MovementType.receipt ||
        MovementType.transfer ||
        MovementType.adjustment => toLocation?.id,
        _ => null,
      },
      toLocationName: switch (_type) {
        MovementType.receipt ||
        MovementType.transfer ||
        MovementType.adjustment => toLocation?.name,
        _ => null,
      },
    );
    Navigator.of(context).pop(
      StockMovement(
        id: movementId,
        movementNumber:
            'MUT-${now.year}-${movementId.substring(movementId.length - 6)}',
        type: _type,
        status: MovementStatus.draft,
        idempotencyKey: idempotencyKey,
        performedBy: 'Admin Sekolah',
        createdAt: now,
        lines: [line],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIssue = _type == MovementType.issue;
    final isTransfer = _type == MovementType.transfer;
    final needsDestination =
        _type == MovementType.receipt ||
        _type == MovementType.transfer ||
        _type == MovementType.adjustment;
    final needsSource = isIssue || isTransfer;

    return AlertDialog(
      title: const Text('Buat Draft Mutasi'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _MovementStatusNotice(compact: true),
                const SizedBox(height: 14),
                DropdownButtonFormField<MovementType>(
                  key: const Key('movement-type-input'),
                  isExpanded: true,
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Jenis mutasi'),
                  items: MovementType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(movementTypeLabel(type)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _type = value);
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  key: const Key('movement-item-input'),
                  isExpanded: true,
                  initialValue: _itemId,
                  decoration: const InputDecoration(labelText: 'Barang'),
                  items: widget.items
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.itemId!,
                          child: Text(
                            '${item.name} (${item.category})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _itemId = value);
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('movement-quantity-input'),
                  controller: _quantityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Jumlah'),
                  validator: _validateQuantity,
                ),
                if (needsSource) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: const Key('movement-source-input'),
                    isExpanded: true,
                    initialValue: _fromLocationId,
                    decoration: InputDecoration(
                      labelText: isIssue
                          ? 'Lokasi asal/pengeluaran'
                          : 'Lokasi asal',
                    ),
                    items: widget.locations
                        .map(
                          (location) => DropdownMenuItem(
                            value: location.id,
                            child: Text(location.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _fromLocationId = value);
                      }
                    },
                  ),
                ],
                if (needsDestination) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: const Key('movement-destination-input'),
                    isExpanded: true,
                    initialValue: _toLocationId,
                    decoration: InputDecoration(
                      labelText: _type == MovementType.adjustment
                          ? 'Lokasi penyesuaian'
                          : 'Lokasi tujuan/penerimaan',
                    ),
                    items: widget.locations
                        .map(
                          (location) => DropdownMenuItem(
                            value: location.id,
                            child: Text(location.name),
                          ),
                        )
                        .toList(),
                    validator: _validateDestination,
                    onChanged: (value) {
                      if (value != null) setState(() => _toLocationId = value);
                    },
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('movement-notes-input'),
                  controller: _notesController,
                  maxLength: 1000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (opsional)',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const Key('save-movement-draft'),
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF168B83),
          ),
          child: const Text('Simpan sebagai draft'),
        ),
      ],
    );
  }
}

// CATATAN PEMELIHARAAN: draft belum mengubah saldo sampai diposting; backend
// memerlukan MongoDB replica set agar saldo, status, dan audit tersimpan atomik.
class _MovementStatusNotice extends StatelessWidget {
  const _MovementStatusNotice({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5E8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF4E0C1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFB77B27),
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              compact
                  ? 'Draft belum mengubah saldo. Posting akan '
                        'memperbarui saldo secara atomik.'
                  : 'Draft tersimpan dan dapat dibatalkan. Posting memvalidasi stok '
                        'lalu memperbarui saldo, status, dan audit secara atomik. '
                        'Posting memerlukan MongoDB replica set.',
              style: const TextStyle(
                color: Color(0xFF795B32),
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementMetric extends StatelessWidget {
  const _MovementMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDF0F4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  value.toString(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementFilter<T> extends StatelessWidget {
  const _MovementFilter({
    super.key,
    required this.value,
    required this.emptyLabel,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final String emptyLabel;
  final List<_FilterOption<T>> options;
  final ValueChanged<T?> onChanged;

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
        child: DropdownButton<T>(
          value: value,
          hint: Text(emptyLabel),
          borderRadius: BorderRadius.circular(12),
          style: const TextStyle(color: Color(0xFF53627A), fontSize: 11),
          items: options
              .map(
                (option) => DropdownMenuItem<T>(
                  value: option.value,
                  child: Text(option.label),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _FilterOption<T> {
  const _FilterOption(this.value, this.label);

  final T value;
  final String label;
}

class _MovementStatusBadge extends StatelessWidget {
  const _MovementStatusBadge({required this.status});

  final MovementStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      MovementStatus.draft => (
        const Color(0xFFFFF3E4),
        const Color(0xFFB77B27),
      ),
      MovementStatus.posted => (
        const Color(0xFFE9F6F0),
        const Color(0xFF368A6C),
      ),
      MovementStatus.cancelled => (
        const Color(0xFFF0F2F5),
        const Color(0xFF8994A7),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        movementStatusLabel(status),
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MovementActions extends StatelessWidget {
  const _MovementActions({
    required this.movement,
    required this.onDetails,
    required this.onCancel,
    required this.onPost,
  });

  final StockMovement movement;
  final VoidCallback onDetails;
  final VoidCallback? onCancel;
  final VoidCallback? onPost;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Aksi ${movement.movementNumber}',
      onSelected: (action) {
        if (action == 'details') onDetails();
        if (action == 'cancel') onCancel?.call();
        if (action == 'post') onPost?.call();
      },
      itemBuilder: (context) => [
        if (onPost != null)
          const PopupMenuItem(
            value: 'post',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.check_circle_outline_rounded, size: 18),
              title: Text('Posting'),
            ),
          ),
        const PopupMenuItem(
          value: 'details',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.visibility_outlined, size: 18),
            title: Text('Lihat detail'),
          ),
        ),
        if (onCancel != null)
          const PopupMenuItem(
            value: 'cancel',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.cancel_outlined, size: 18),
              title: Text('Batalkan draft'),
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

class _MovementCard extends StatelessWidget {
  const _MovementCard({
    required this.movement,
    required this.onDetails,
    required this.onCancel,
    required this.onPost,
  });

  final StockMovement movement;
  final VoidCallback onDetails;
  final VoidCallback? onCancel;
  final VoidCallback? onPost;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFE),
        border: Border.all(color: const Color(0xFFEDF0F4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  movement.movementNumber,
                  style: const TextStyle(
                    color: Color(0xFF263752),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _MovementActions(
                movement: movement,
                onDetails: onDetails,
                onCancel: onCancel,
                onPost: onPost,
              ),
            ],
          ),
          Text(
            '${movementTypeLabel(movement.type)} · ${_formatDate(movement.createdAt)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(_itemsSummary(movement)),
          Text(
            '${_quantitySummary(movement)} · ${_routeSummary(movement)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          _MovementStatusBadge(status: movement.status),
        ],
      ),
    );
  }
}

class _MovementPagination extends StatelessWidget {
  const _MovementPagination({
    required this.currentPage,
    required this.pageCount,
    required this.firstIndex,
    required this.lastIndex,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentPage;
  final int pageCount;
  final int firstIndex;
  final int lastIndex;
  final int total;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Menampilkan $firstIndex–$lastIndex dari $total mutasi',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        IconButton(
          key: const Key('movement-page-previous'),
          tooltip: 'Halaman mutasi sebelumnya',
          onPressed: currentPage > 0 ? onPrevious : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text(
          '${currentPage + 1} / $pageCount',
          key: const Key('movement-page-indicator'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        IconButton(
          key: const Key('movement-page-next'),
          tooltip: 'Halaman mutasi berikutnya',
          onPressed: currentPage < pageCount - 1 ? onNext : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _EmptyMovements extends StatelessWidget {
  const _EmptyMovements({
    required this.hasAnyMovement,
    required this.onCreate,
    required this.canCreate,
  });

  final bool hasAnyMovement;
  final VoidCallback onCreate;
  final bool canCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 12),
      child: Center(
        child: Column(
          children: [
            const Icon(
              Icons.swap_horiz_rounded,
              size: 34,
              color: Color(0xFF9AA5B5),
            ),
            const SizedBox(height: 10),
            Text(
              hasAnyMovement
                  ? 'Mutasi tidak ditemukan'
                  : 'Belum ada mutasi barang',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              hasAnyMovement
                  ? 'Ubah kata kunci atau filter, lalu coba lagi.'
                  : canCreate
                  ? 'Buat draft untuk mulai mencatat pergerakan barang.'
                  : 'Belum ada pergerakan barang yang tercatat.',
            ),
            if (!hasAnyMovement && canCreate) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Buat Mutasi'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

void _showMovementDetails(BuildContext context, StockMovement movement) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(movement.movementNumber),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MovementDetailLine(
                label: 'Jenis',
                value: movementTypeLabel(movement.type),
              ),
              _MovementDetailLine(
                label: 'Status',
                value: movementStatusLabel(movement.status),
              ),
              _MovementDetailLine(
                label: 'Tanggal',
                value: _formatDate(movement.createdAt),
              ),
              _MovementDetailLine(
                label: 'Petugas',
                value: movement.performedBy,
              ),
              const Divider(height: 22),
              for (final (index, line) in movement.lines.indexed) ...[
                Text(
                  'Baris ${index + 1}: ${line.itemName}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                _MovementDetailLine(
                  label: 'Jumlah',
                  value: _formatQuantity(line.quantity),
                ),
                _MovementDetailLine(
                  label: 'Dari',
                  value: line.fromLocationName ?? '-',
                ),
                _MovementDetailLine(
                  label: 'Ke',
                  value: line.toLocationName ?? '-',
                ),
                _MovementDetailLine(
                  label: 'Catatan',
                  value: line.notes.isEmpty ? '-' : line.notes,
                ),
              ],
              const SizedBox(height: 8),
              const _MovementStatusNotice(compact: true),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    ),
  );
}

class _MovementDetailLine extends StatelessWidget {
  const _MovementDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          const Text(': '),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

String _itemsSummary(StockMovement movement) {
  if (movement.lines.isEmpty) return '-';
  final first = movement.lines.first.itemName;
  final remaining = movement.lines.length - 1;
  return remaining == 0 ? first : '$first + $remaining barang';
}

String _quantitySummary(StockMovement movement) {
  final total = movement.lines.fold<double>(
    0,
    (sum, line) => sum + line.quantity,
  );
  return _formatQuantity(total);
}

String _routeSummary(StockMovement movement) {
  final line = movement.lines.firstOrNull;
  if (line == null) return '-';
  if (line.fromLocationName != null && line.toLocationName != null) {
    return '${line.fromLocationName} → ${line.toLocationName}';
  }
  return line.fromLocationName ?? line.toLocationName ?? '-';
}

String _formatQuantity(double quantity) {
  return quantity == quantity.roundToDouble()
      ? quantity.toInt().toString()
      : quantity.toString();
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
  final local = date.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day ${months[local.month - 1]} ${local.year}, $hour:$minute';
}
