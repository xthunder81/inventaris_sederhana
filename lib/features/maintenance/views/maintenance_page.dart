// CATATAN PEMELIHARAAN: page mengirim intent create/transisi ke parent; parent
// menunggu API sebelum mengganti record agar kegagalan tidak tampak tersimpan.
import 'package:flutter/material.dart';

import '../../inventory/models/inventory_item.dart';
import '../models/maintenance_record.dart';

const _maintenancePageSize = 8;

class MaintenancePage extends StatefulWidget {
  const MaintenancePage({
    super.key,
    required this.records,
    required this.items,
    required this.searchQuery,
    required this.onCreate,
    required this.onUpdate,
    this.canManageMaintenance = true,
  });

  final List<MaintenanceRecord> records;
  final List<InventoryItem> items;
  final String searchQuery;
  final Future<void> Function(MaintenanceRecord) onCreate;
  final Future<void> Function(MaintenanceRecord) onUpdate;
  final bool canManageMaintenance;

  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  MaintenanceStatus? _statusFilter;
  int _currentPage = 0;

  List<MaintenanceRecord> get _filteredRecords {
    final query = widget.searchQuery.trim().toLowerCase();
    return widget.records.where((record) {
      final matchesQuery =
          query.isEmpty ||
          record.assetName.toLowerCase().contains(query) ||
          record.assetCode.toLowerCase().contains(query) ||
          record.description.toLowerCase().contains(query) ||
          record.reportedBy.toLowerCase().contains(query) ||
          maintenanceStatusLabel(record.status).toLowerCase().contains(query);
      return matchesQuery &&
          (_statusFilter == null || record.status == _statusFilter);
    }).toList();
  }

  @override
  void didUpdateWidget(covariant MaintenancePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) _currentPage = 0;
    final pageCount =
        (_filteredRecords.length + _maintenancePageSize - 1) ~/
        _maintenancePageSize;
    if (pageCount == 0) {
      _currentPage = 0;
    } else if (_currentPage >= pageCount) {
      _currentPage = pageCount - 1;
    }
  }

  Future<void> _openCreateDialog() async {
    if (widget.items.isEmpty) return;
    final result = await showDialog<MaintenanceRecord>(
      context: context,
      builder: (context) => MaintenanceCreateDialog(items: widget.items),
    );
    if (result != null && mounted) await widget.onCreate(result);
  }

  Future<void> _start(MaintenanceRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mulai pemeliharaan?'),
        content: Text(
          'Laporan untuk ${record.assetName} akan berstatus sedang dikerjakan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            key: const Key('maintenance-confirm-start'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mulai'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.onUpdate(record.copyWith(status: MaintenanceStatus.inProgress));
    }
  }

  Future<void> _complete(MaintenanceRecord record) async {
    final updated = await showDialog<MaintenanceRecord>(
      context: context,
      builder: (context) => MaintenanceCompletionDialog(record: record),
    );
    if (updated != null && mounted) await widget.onUpdate(updated);
  }

  Future<void> _cancel(MaintenanceRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan laporan pemeliharaan?'),
        content: const Text(
          'Laporan akan ditutup sebagai dibatalkan. Kondisi aset tidak berubah.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            key: const Key('maintenance-confirm-cancel'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Batalkan laporan'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.onUpdate(
        record.copyWith(
          status: MaintenanceStatus.cancelled,
          closedAt: DateTime.now(),
        ),
      );
    }
  }

  void _showDetails(MaintenanceRecord record) {
    showDialog<void>(
      context: context,
      builder: (context) => _MaintenanceDetailsDialog(record: record),
    );
  }

  @override
  Widget build(BuildContext context) {
    final records = _filteredRecords;
    final pageCount =
        (records.length + _maintenancePageSize - 1) ~/ _maintenancePageSize;
    final firstIndex = _currentPage * _maintenancePageSize;
    final visible = records
        .skip(firstIndex)
        .take(_maintenancePageSize)
        .toList();
    final reportedCount = _count(MaintenanceStatus.reported);
    final inProgressCount = _count(MaintenanceStatus.inProgress);
    final completedCount = _count(MaintenanceStatus.completed);
    final cancelledCount = _count(MaintenanceStatus.cancelled);

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
                  'Pemeliharaan',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  widget.canManageMaintenance
                      ? 'Catat laporan kerusakan dan pantau proses perbaikan aset.'
                      : 'Lihat laporan kerusakan dan status perbaikan aset.',
                ),
              ],
            );
            final addButton = FilledButton.icon(
              key: const Key('maintenance-create'),
              onPressed: widget.items.isEmpty ? null : _openCreateDialog,
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('Buat Laporan'),
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
                  if (widget.canManageMaintenance) ...[
                    const SizedBox(height: 16),
                    addButton,
                  ],
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: heading),
                if (widget.canManageMaintenance) addButton,
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        const _MaintenanceNotice(),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1000
                ? 4
                : constraints.maxWidth >= 520
                ? 2
                : 1;
            const spacing = 12.0;
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            final metrics = [
              _MaintenanceMetric(
                label: 'Dilaporkan',
                value: reportedCount,
                icon: Icons.flag_outlined,
                color: const Color(0xFFE59B3F),
              ),
              _MaintenanceMetric(
                label: 'Sedang dikerjakan',
                value: inProgressCount,
                icon: Icons.home_repair_service_outlined,
                color: const Color(0xFF5677C8),
              ),
              _MaintenanceMetric(
                label: 'Selesai',
                value: completedCount,
                icon: Icons.check_circle_outline_rounded,
                color: const Color(0xFF42A786),
              ),
              _MaintenanceMetric(
                label: 'Dibatalkan',
                value: cancelledCount,
                icon: Icons.cancel_outlined,
                color: const Color(0xFF8994A7),
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
                        'Daftar Pemeliharaan',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${records.length} laporan ditampilkan',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  );
                  final filter = _MaintenanceStatusFilter(
                    value: _statusFilter,
                    onChanged: (value) => setState(() {
                      _statusFilter = value;
                      _currentPage = 0;
                    }),
                  );
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [heading, const SizedBox(height: 12), filter],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: heading),
                      filter,
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              if (records.isEmpty)
                _EmptyMaintenance(
                  hasAnyRecord: widget.records.isNotEmpty,
                  onCreate: _openCreateDialog,
                  canCreate: widget.canManageMaintenance,
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 760) {
                      return Column(
                        children: visible
                            .map(
                              (record) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _MaintenanceCard(
                                  record: record,
                                  onDetails: () => _showDetails(record),
                                  onStart: widget.canManageMaintenance
                                      ? () => _start(record)
                                      : null,
                                  onComplete: widget.canManageMaintenance
                                      ? () => _complete(record)
                                      : null,
                                  onCancel: widget.canManageMaintenance
                                      ? () => _cancel(record)
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
                              DataColumn(label: Text('ASET')),
                              DataColumn(label: Text('LAPORAN')),
                              DataColumn(label: Text('TANGGAL')),
                              DataColumn(label: Text('BIAYA')),
                              DataColumn(label: Text('STATUS')),
                              DataColumn(label: Text('AKSI')),
                            ],
                            rows: visible
                                .map(
                                  (record) => DataRow(
                                    cells: [
                                      DataCell(
                                        SizedBox(
                                          width: 190,
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                record.assetName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                record.assetCode,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 240,
                                          child: Text(
                                            record.description,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(_formatDate(record.reportedAt)),
                                      ),
                                      DataCell(
                                        Text(_formatCurrency(record.cost)),
                                      ),
                                      DataCell(
                                        _MaintenanceStatusBadge(
                                          status: record.status,
                                        ),
                                      ),
                                      DataCell(
                                        widget.canManageMaintenance
                                            ? _MaintenanceActions(
                                                record: record,
                                                onDetails: () =>
                                                    _showDetails(record),
                                                onStart: () => _start(record),
                                                onComplete: () =>
                                                    _complete(record),
                                                onCancel: () => _cancel(record),
                                              )
                                            : const SizedBox.shrink(),
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
              if (records.length > _maintenancePageSize) ...[
                const SizedBox(height: 12),
                _MaintenancePagination(
                  currentPage: _currentPage,
                  pageCount: pageCount,
                  firstIndex: firstIndex + 1,
                  lastIndex: firstIndex + visible.length,
                  total: records.length,
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

  int _count(MaintenanceStatus status) =>
      widget.records.where((record) => record.status == status).length;
}

class _MaintenanceNotice extends StatelessWidget {
  const _MaintenanceNotice();

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
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFFB77B27), size: 18),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Status laporan tidak mengubah kondisi aset secara otomatis. '
              'Setelah pemeliharaan, periksa aset dan catat kondisi melalui '
              'aksi inventaris agar riwayat kondisi tetap terpisah.',
              style: TextStyle(
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

class _MaintenanceMetric extends StatelessWidget {
  const _MaintenanceMetric({
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
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFEDF0F4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 10),
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
                Text('$value', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MaintenanceStatusBadge extends StatelessWidget {
  const _MaintenanceStatusBadge({required this.status});

  final MaintenanceStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      MaintenanceStatus.reported => (
        const Color(0xFFFFF3E4),
        const Color(0xFFB77B27),
      ),
      MaintenanceStatus.inProgress => (
        const Color(0xFFEDF1FF),
        const Color(0xFF5677C8),
      ),
      MaintenanceStatus.completed => (
        const Color(0xFFEAF6F0),
        const Color(0xFF368A6C),
      ),
      MaintenanceStatus.cancelled => (
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
        maintenanceStatusLabel(status),
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MaintenanceStatusFilter extends StatelessWidget {
  const _MaintenanceStatusFilter({
    required this.value,
    required this.onChanged,
  });

  final MaintenanceStatus? value;
  final ValueChanged<MaintenanceStatus?> onChanged;

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
        child: DropdownButton<MaintenanceStatus?>(
          key: const Key('maintenance-status-filter'),
          value: value,
          hint: const Text('Semua status'),
          borderRadius: BorderRadius.circular(12),
          items: [
            const DropdownMenuItem<MaintenanceStatus?>(
              value: null,
              child: Text('Semua status'),
            ),
            ...MaintenanceStatus.values.map(
              (status) => DropdownMenuItem<MaintenanceStatus?>(
                value: status,
                child: Text(maintenanceStatusLabel(status)),
              ),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _MaintenanceActions extends StatelessWidget {
  const _MaintenanceActions({
    required this.record,
    required this.onDetails,
    required this.onStart,
    required this.onComplete,
    required this.onCancel,
  });

  final MaintenanceRecord record;
  final VoidCallback onDetails;
  final VoidCallback onStart;
  final VoidCallback onComplete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Aksi ${record.assetName}',
      onSelected: (action) {
        switch (action) {
          case 'details':
            onDetails();
          case 'start':
            onStart();
          case 'complete':
            onComplete();
          case 'cancel':
            onCancel();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'details',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.visibility_outlined, size: 18),
            title: Text('Lihat detail'),
          ),
        ),
        if (record.status == MaintenanceStatus.reported)
          const PopupMenuItem(
            value: 'start',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.play_circle_outline_rounded, size: 18),
              title: Text('Mulai pemeliharaan'),
            ),
          ),
        if (record.status == MaintenanceStatus.inProgress)
          const PopupMenuItem(
            value: 'complete',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.task_alt_rounded, size: 18),
              title: Text('Tandai selesai'),
            ),
          ),
        if (record.status == MaintenanceStatus.reported ||
            record.status == MaintenanceStatus.inProgress)
          const PopupMenuItem(
            value: 'cancel',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.cancel_outlined, size: 18),
              title: Text('Batalkan laporan'),
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

class _MaintenanceCard extends StatelessWidget {
  const _MaintenanceCard({
    required this.record,
    required this.onDetails,
    required this.onStart,
    required this.onComplete,
    required this.onCancel,
  });

  final MaintenanceRecord record;
  final VoidCallback onDetails;
  final VoidCallback? onStart;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;

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
                  record.assetName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF263752),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onStart != null)
                _MaintenanceActions(
                  record: record,
                  onDetails: onDetails,
                  onStart: onStart!,
                  onComplete: onComplete!,
                  onCancel: onCancel!,
                ),
            ],
          ),
          Text(record.assetCode, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Text(
            record.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _formatDate(record.reportedAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                _formatCurrency(record.cost),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              _MaintenanceStatusBadge(status: record.status),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyMaintenance extends StatelessWidget {
  const _EmptyMaintenance({
    required this.hasAnyRecord,
    required this.onCreate,
    required this.canCreate,
  });

  final bool hasAnyRecord;
  final VoidCallback onCreate;
  final bool canCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
      child: Center(
        child: Column(
          children: [
            const Icon(
              Icons.home_repair_service_outlined,
              size: 36,
              color: Color(0xFF9AA5B5),
            ),
            const SizedBox(height: 10),
            Text(
              hasAnyRecord
                  ? 'Laporan tidak ditemukan'
                  : 'Belum ada laporan pemeliharaan',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              hasAnyRecord
                  ? 'Ubah kata kunci atau filter, lalu coba lagi.'
                  : canCreate
                  ? 'Laporkan kerusakan aset untuk memulai pencatatan.'
                  : 'Belum ada laporan pemeliharaan yang tercatat.',
            ),
            if (!hasAnyRecord && canCreate) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Buat Laporan'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MaintenancePagination extends StatelessWidget {
  const _MaintenancePagination({
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
            'Menampilkan $firstIndex–$lastIndex dari $total laporan',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        IconButton(
          key: const Key('maintenance-page-previous'),
          tooltip: 'Halaman pemeliharaan sebelumnya',
          onPressed: currentPage > 0 ? onPrevious : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text(
          '${currentPage + 1} / $pageCount',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        IconButton(
          key: const Key('maintenance-page-next'),
          tooltip: 'Halaman pemeliharaan berikutnya',
          onPressed: currentPage < pageCount - 1 ? onNext : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class MaintenanceCreateDialog extends StatefulWidget {
  const MaintenanceCreateDialog({super.key, required this.items});

  final List<InventoryItem> items;

  @override
  State<MaintenanceCreateDialog> createState() =>
      _MaintenanceCreateDialogState();
}

class _MaintenanceCreateDialogState extends State<MaintenanceCreateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  late String _assetCode;

  @override
  void initState() {
    super.initState();
    _assetCode = widget.items.first.code;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final asset = widget.items.firstWhere((item) => item.code == _assetCode);
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toString();
    // CATATAN PEMELIHARAAN: backend membuat ID laporan dan mengambil pelapor
    // dari token; form hanya mengirim ID aset dan deskripsi keluhan.
    Navigator.pop(
      context,
      MaintenanceRecord(
        id: id,
        assetId: asset.assetId ?? '',
        assetCode: asset.code,
        assetName: asset.name,
        reportedBy: 'Admin Sekolah',
        status: MaintenanceStatus.reported,
        description: _descriptionController.text.trim(),
        cost: 0,
        reportedAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Buat Laporan Pemeliharaan'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _MaintenanceNotice(),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  key: const Key('maintenance-asset-input'),
                  isExpanded: true,
                  initialValue: _assetCode,
                  decoration: const InputDecoration(labelText: 'Aset'),
                  items: widget.items
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.code,
                          child: Text(
                            '${item.name} (${item.code})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _assetCode = value);
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('maintenance-description-input'),
                  controller: _descriptionController,
                  maxLength: 4000,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Keluhan/kerusakan',
                    hintText: 'Jelaskan gejala dan bagian yang perlu diperiksa',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Keluhan wajib diisi'
                      : null,
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Status awal: Dilaporkan · Biaya: Rp 0 sampai pekerjaan selesai.',
                    style: TextStyle(color: Color(0xFF69778D), fontSize: 11),
                  ),
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
          key: const Key('maintenance-save-report'),
          onPressed: _submit,
          child: const Text('Simpan laporan'),
        ),
      ],
    );
  }
}

class MaintenanceCompletionDialog extends StatefulWidget {
  const MaintenanceCompletionDialog({super.key, required this.record});

  final MaintenanceRecord record;

  @override
  State<MaintenanceCompletionDialog> createState() =>
      _MaintenanceCompletionDialogState();
}

class _MaintenanceCompletionDialogState
    extends State<MaintenanceCompletionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _costController;

  @override
  void initState() {
    super.initState();
    _costController = TextEditingController(
      text: widget.record.cost == 0
          ? ''
          : widget.record.cost.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _costController.dispose();
    super.dispose();
  }

  String? _validateCost(String? value) {
    final cost = double.tryParse((value ?? '').trim());
    if (cost == null || !cost.isFinite || cost < 0) {
      return 'Masukkan biaya akhir (minimal Rp 0)';
    }
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      widget.record.copyWith(
        status: MaintenanceStatus.completed,
        cost: double.parse(_costController.text.trim()),
        closedAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Selesaikan Pemeliharaan'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Aset: ${widget.record.assetName}'),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('maintenance-final-cost-input'),
                controller: _costController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Biaya akhir (Rp)',
                ),
                validator: _validateCost,
              ),
              const SizedBox(height: 8),
              const Text(
                'Penyelesaian laporan tidak mengubah kondisi aset otomatis. '
                'Periksa aset lalu catat kondisinya melalui halaman Inventaris.',
                style: TextStyle(color: Color(0xFF69778D), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kembali'),
        ),
        FilledButton(
          key: const Key('maintenance-save-completion'),
          onPressed: _submit,
          child: const Text('Simpan selesai'),
        ),
      ],
    );
  }
}

class _MaintenanceDetailsDialog extends StatelessWidget {
  const _MaintenanceDetailsDialog({required this.record});

  final MaintenanceRecord record;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Detail Pemeliharaan'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MaintenanceDetailLine(label: 'Aset', value: record.assetName),
              _MaintenanceDetailLine(
                label: 'Kode aset',
                value: record.assetCode,
              ),
              _MaintenanceDetailLine(
                label: 'Dilaporkan oleh',
                value: record.reportedBy,
              ),
              _MaintenanceDetailLine(
                label: 'Tanggal laporan',
                value: _formatDate(record.reportedAt),
              ),
              _MaintenanceDetailLine(
                label: 'Status',
                value: maintenanceStatusLabel(record.status),
              ),
              _MaintenanceDetailLine(
                label: 'Biaya',
                value: _formatCurrency(record.cost),
              ),
              if (record.closedAt != null)
                _MaintenanceDetailLine(
                  label: 'Ditutup pada',
                  value: _formatDate(record.closedAt!),
                ),
              const SizedBox(height: 8),
              const Text(
                'Keluhan/kerusakan',
                style: TextStyle(
                  color: Color(0xFF53627A),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(record.description),
              const SizedBox(height: 12),
              const _MaintenanceNotice(),
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
    );
  }
}

class _MaintenanceDetailLine extends StatelessWidget {
  const _MaintenanceDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          const Text(': '),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _formatCurrency(double value) {
  final digits = value.toStringAsFixed(0);
  final grouped = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => '.',
  );
  return 'Rp $grouped';
}
