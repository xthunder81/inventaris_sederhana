// CATATAN MOCKUP: laporan dirangkum dari daftar lokal Inventaris, Mutasi,
// dan Pemeliharaan yang diterima dari parent. Filter periode hanya berlaku
// untuk aktivitas bertanggal; data aset saat ini tidak menyimpan tanggal masuk.
import 'package:flutter/material.dart';

import '../../inventory/models/inventory_item.dart';
import '../../maintenance/models/maintenance_record.dart';
import '../../movements/models/stock_movement.dart';

enum _ReportSection { overview, inventory, movements, maintenance }

enum _ReportPeriod { all, days30, days365 }

class ReportsPage extends StatefulWidget {
  const ReportsPage({
    super.key,
    required this.items,
    required this.movements,
    required this.maintenanceRecords,
    required this.searchQuery,
    this.canExport = true,
  });

  final List<InventoryItem> items;
  final List<StockMovement> movements;
  final List<MaintenanceRecord> maintenanceRecords;
  final String searchQuery;
  final bool canExport;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  _ReportSection _section = _ReportSection.overview;
  _ReportPeriod _period = _ReportPeriod.all;

  DateTime? get _periodStart => switch (_period) {
    _ReportPeriod.all => null,
    _ReportPeriod.days30 => DateTime.now().subtract(const Duration(days: 30)),
    _ReportPeriod.days365 => DateTime.now().subtract(const Duration(days: 365)),
  };

  List<InventoryItem> get _filteredItems {
    final query = widget.searchQuery.trim().toLowerCase();
    return widget.items.where((item) {
      return query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.code.toLowerCase().contains(query) ||
          item.category.toLowerCase().contains(query) ||
          item.location.toLowerCase().contains(query) ||
          item.condition.toLowerCase().contains(query);
    }).toList();
  }

  List<StockMovement> get _filteredMovements {
    final query = widget.searchQuery.trim().toLowerCase();
    final start = _periodStart;
    return widget.movements.where((movement) {
      final matchesPeriod =
          start == null || !movement.createdAt.isBefore(start);
      final matchesQuery =
          query.isEmpty ||
          movement.movementNumber.toLowerCase().contains(query) ||
          movementTypeLabel(movement.type).toLowerCase().contains(query) ||
          movementStatusLabel(movement.status).toLowerCase().contains(query) ||
          movement.lines.any(
            (line) => line.itemName.toLowerCase().contains(query),
          );
      return matchesPeriod && matchesQuery;
    }).toList();
  }

  List<MaintenanceRecord> get _filteredMaintenance {
    final query = widget.searchQuery.trim().toLowerCase();
    final start = _periodStart;
    return widget.maintenanceRecords.where((record) {
      final matchesPeriod = start == null || !record.reportedAt.isBefore(start);
      final matchesQuery =
          query.isEmpty ||
          record.assetName.toLowerCase().contains(query) ||
          record.assetCode.toLowerCase().contains(query) ||
          record.description.toLowerCase().contains(query) ||
          maintenanceStatusLabel(record.status).toLowerCase().contains(query);
      return matchesPeriod && matchesQuery;
    }).toList();
  }

  Future<void> _openExportPreview() async {
    final periodLabel = _periodLabel(_period);
    final section = _section;
    await showDialog<void>(
      context: context,
      builder: (context) => _ReportExportPreviewDialog(
        section: section,
        periodLabel: periodLabel,
        items: _filteredItems,
        movements: _filteredMovements,
        maintenanceRecords: _filteredMaintenance,
        onMockDownload: (format) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text('Unduh $format masih mockup; file belum dibuat.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;
    final movements = _filteredMovements;
    final maintenance = _filteredMaintenance;
    final needsAttention = items
        .where((item) => item.condition != 'Bagus')
        .length;
    final activeMaintenance = maintenance
        .where(
          (record) =>
              record.status == MaintenanceStatus.reported ||
              record.status == MaintenanceStatus.inProgress,
        )
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final heading = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Laporan',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Ringkasan kondisi aset, transaksi mutasi, dan pemeliharaan.',
                ),
              ],
            );
            final controls = Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _ReportSelector<_ReportSection>(
                  key: const Key('report-section-filter'),
                  value: _section,
                  label: 'Jenis laporan',
                  options: _ReportSection.values
                      .map(
                        (section) =>
                            _ReportOption(section, _sectionLabel(section)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _section = value),
                ),
                _ReportSelector<_ReportPeriod>(
                  key: const Key('report-period-filter'),
                  value: _period,
                  label: 'Periode',
                  options: const [
                    _ReportOption(_ReportPeriod.all, 'Semua periode'),
                    _ReportOption(_ReportPeriod.days30, '30 hari terakhir'),
                    _ReportOption(_ReportPeriod.days365, '12 bulan terakhir'),
                  ],
                  onChanged: (value) => setState(() => _period = value),
                ),
                if (widget.canExport)
                  OutlinedButton.icon(
                    key: const Key('report-export'),
                    onPressed: _openExportPreview,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Ekspor'),
                  ),
              ],
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, const SizedBox(height: 16), controls],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: heading),
                controls,
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        const _ReportMockupNotice(),
        const SizedBox(height: 16),
        _buildSelectedReport(
          context,
          items: items,
          movements: movements,
          maintenance: maintenance,
          needsAttention: needsAttention,
          activeMaintenance: activeMaintenance,
        ),
      ],
    );
  }

  Widget _buildSelectedReport(
    BuildContext context, {
    required List<InventoryItem> items,
    required List<StockMovement> movements,
    required List<MaintenanceRecord> maintenance,
    required int needsAttention,
    required int activeMaintenance,
  }) {
    return switch (_section) {
      _ReportSection.overview => _OverviewReport(
        items: items,
        movements: movements,
        maintenance: maintenance,
        needsAttention: needsAttention,
        activeMaintenance: activeMaintenance,
      ),
      _ReportSection.inventory => _InventoryReport(items: items),
      _ReportSection.movements => _MovementReport(movements: movements),
      _ReportSection.maintenance => _MaintenanceReport(records: maintenance),
    };
  }
}

enum _ExportFormat { pdf, csv }

/// CATATAN MOCKUP: dialog ini hanya memperlihatkan contoh tata letak/isi
/// dokumen berdasarkan filter aktif. Untuk produksi, hasil yang sama harus
/// dibentuk menjadi file PDF/CSV dan diunduh, bukan dari teks presentasi UI.
class _ReportExportPreviewDialog extends StatefulWidget {
  const _ReportExportPreviewDialog({
    required this.section,
    required this.periodLabel,
    required this.items,
    required this.movements,
    required this.maintenanceRecords,
    required this.onMockDownload,
  });

  final _ReportSection section;
  final String periodLabel;
  final List<InventoryItem> items;
  final List<StockMovement> movements;
  final List<MaintenanceRecord> maintenanceRecords;
  final ValueChanged<String> onMockDownload;

  @override
  State<_ReportExportPreviewDialog> createState() =>
      _ReportExportPreviewDialogState();
}

class _ReportExportPreviewDialogState
    extends State<_ReportExportPreviewDialog> {
  _ExportFormat _format = _ExportFormat.pdf;

  List<List<String>> get _csvRows => switch (widget.section) {
    _ReportSection.overview => _overviewCsvRows,
    _ReportSection.inventory =>
      widget.items
          .map(
            (item) => [
              item.code,
              item.name,
              item.category,
              item.location,
              item.condition,
            ],
          )
          .toList(),
    _ReportSection.movements =>
      widget.movements
          .expand(
            (movement) => movement.lines.map(
              (line) => [
                movement.movementNumber,
                _formatDate(movement.createdAt),
                movementTypeLabel(movement.type),
                movementStatusLabel(movement.status),
                line.itemName,
                _formatQuantity(line.quantity),
              ],
            ),
          )
          .toList(),
    _ReportSection.maintenance =>
      widget.maintenanceRecords
          .map(
            (record) => [
              record.assetCode,
              record.assetName,
              record.description,
              maintenanceStatusLabel(record.status),
              _formatCurrency(record.cost),
              _formatDate(record.reportedAt),
            ],
          )
          .toList(),
  };

  List<String> get _csvHeaders => switch (widget.section) {
    _ReportSection.overview => const ['bagian', 'metrik', 'nilai'],
    _ReportSection.inventory => const [
      'kode_aset',
      'nama_aset',
      'kategori',
      'lokasi',
      'kondisi',
    ],
    _ReportSection.movements => const [
      'nomor_mutasi',
      'tanggal',
      'jenis',
      'status',
      'nama_barang',
      'jumlah',
    ],
    _ReportSection.maintenance => const [
      'kode_aset',
      'nama_aset',
      'keluhan',
      'status',
      'biaya',
      'tanggal_laporan',
    ],
  };

  List<List<String>> get _overviewCsvRows {
    final conditions = _countBy(widget.items, (item) => item.condition);
    final posted = widget.movements
        .where((item) => item.status == MovementStatus.posted)
        .length;
    final drafts = widget.movements
        .where((item) => item.status == MovementStatus.draft)
        .length;
    final cancelled = widget.movements
        .where((item) => item.status == MovementStatus.cancelled)
        .length;
    final activeMaintenance = widget.maintenanceRecords
        .where(
          (record) =>
              record.status == MaintenanceStatus.reported ||
              record.status == MaintenanceStatus.inProgress,
        )
        .length;
    return [
      ['Inventaris', 'Aset tercatat', '${widget.items.length}'],
      ...conditions.entries.map(
        (entry) => ['Inventaris', 'Kondisi: ${entry.key}', '${entry.value}'],
      ),
      ['Mutasi', 'Total', '${widget.movements.length}'],
      ['Mutasi', 'Draft', '$drafts'],
      ['Mutasi', 'Diposting', '$posted'],
      ['Mutasi', 'Dibatalkan', '$cancelled'],
      ['Pemeliharaan', 'Total laporan', '${widget.maintenanceRecords.length}'],
      ['Pemeliharaan', 'Aktif', '$activeMaintenance'],
    ];
  }

  List<_ExportSummary> get _pdfSummary => switch (widget.section) {
    _ReportSection.overview => [
      _ExportSummary('Aset tercatat', '${widget.items.length}'),
      _ExportSummary(
        'Perlu perhatian',
        '${widget.items.where((item) => item.condition != 'Bagus').length}',
      ),
      _ExportSummary('Mutasi', '${widget.movements.length}'),
      _ExportSummary(
        'Pemeliharaan aktif',
        '${widget.maintenanceRecords.where((record) => record.status == MaintenanceStatus.reported || record.status == MaintenanceStatus.inProgress).length}',
      ),
    ],
    _ReportSection.inventory => [
      _ExportSummary('Aset tercatat', '${widget.items.length}'),
      _ExportSummary(
        'Kondisi bagus',
        '${widget.items.where((item) => item.condition == 'Bagus').length}',
      ),
      _ExportSummary(
        'Dalam service',
        '${widget.items.where((item) => item.condition == 'Dalam service').length}',
      ),
      _ExportSummary(
        'Rusak',
        '${widget.items.where((item) => item.condition == 'Rusak').length}',
      ),
    ],
    _ReportSection.movements => [
      _ExportSummary('Total mutasi', '${widget.movements.length}'),
      _ExportSummary(
        'Draft',
        '${widget.movements.where((item) => item.status == MovementStatus.draft).length}',
      ),
      _ExportSummary(
        'Diposting',
        '${widget.movements.where((item) => item.status == MovementStatus.posted).length}',
      ),
      _ExportSummary(
        'Dibatalkan',
        '${widget.movements.where((item) => item.status == MovementStatus.cancelled).length}',
      ),
    ],
    _ReportSection.maintenance => [
      _ExportSummary('Total laporan', '${widget.maintenanceRecords.length}'),
      _ExportSummary(
        'Aktif',
        '${widget.maintenanceRecords.where((record) => record.status == MaintenanceStatus.reported || record.status == MaintenanceStatus.inProgress).length}',
      ),
      _ExportSummary(
        'Selesai',
        '${widget.maintenanceRecords.where((record) => record.status == MaintenanceStatus.completed).length}',
      ),
      _ExportSummary(
        'Biaya selesai',
        _formatCurrency(
          widget.maintenanceRecords
              .where((record) => record.status == MaintenanceStatus.completed)
              .fold<double>(0, (total, record) => total + record.cost),
        ),
      ),
    ],
  };

  List<String> get _pdfDetails => switch (widget.section) {
    _ReportSection.overview || _ReportSection.inventory =>
      widget.items
          .take(6)
          .map(
            (item) =>
                '${item.code} · ${item.name} · ${item.condition} · ${item.location}',
          )
          .toList(),
    _ReportSection.movements =>
      widget.movements
          .take(6)
          .map(
            (movement) =>
                '${movement.movementNumber} · ${movementTypeLabel(movement.type)} · ${movementStatusLabel(movement.status)}',
          )
          .toList(),
    _ReportSection.maintenance =>
      widget.maintenanceRecords
          .take(6)
          .map(
            (record) =>
                '${record.assetCode} · ${record.assetName} · ${maintenanceStatusLabel(record.status)}',
          )
          .toList(),
  };

  String get _csvText {
    final rows = [_csvHeaders, ..._csvRows.take(8)];
    return rows.map((row) => row.map(_escapeCsv).join(',')).join('\n');
  }

  void _downloadMockup() {
    widget.onMockDownload(_format == _ExportFormat.pdf ? 'PDF' : 'CSV');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('report-export-preview'),
      title: const Text('Pratinjau Export Laporan'),
      content: SizedBox(
        width: 580,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<_ExportFormat>(
              key: const Key('report-export-format'),
              segments: const [
                ButtonSegment(
                  value: _ExportFormat.pdf,
                  label: Text('PDF'),
                  icon: Icon(Icons.picture_as_pdf_outlined),
                ),
                ButtonSegment(
                  value: _ExportFormat.csv,
                  label: Text('CSV'),
                  icon: Icon(Icons.table_chart_outlined),
                ),
              ],
              selected: {_format},
              onSelectionChanged: (selection) {
                setState(() => _format = selection.first);
              },
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: SingleChildScrollView(
                child: _format == _ExportFormat.pdf
                    ? _PdfReportPreview(
                        section: widget.section,
                        periodLabel: widget.periodLabel,
                        summary: _pdfSummary,
                        details: _pdfDetails,
                      )
                    : _CsvReportPreview(
                        content: _csvText,
                        headers: _csvHeaders,
                        rowCount: _csvRows.length,
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('report-export-preview-close'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
        FilledButton.icon(
          key: const Key('report-export-preview-download'),
          onPressed: _downloadMockup,
          icon: const Icon(Icons.download_outlined, size: 18),
          label: Text(_format == _ExportFormat.pdf ? 'Unduh PDF' : 'Unduh CSV'),
        ),
      ],
    );
  }
}

class _ExportSummary {
  const _ExportSummary(this.label, this.value);

  final String label;
  final String value;
}

class _PdfReportPreview extends StatelessWidget {
  const _PdfReportPreview({
    required this.section,
    required this.periodLabel,
    required this.summary,
    required this.details,
  });

  final _ReportSection section;
  final String periodLabel;
  final List<_ExportSummary> summary;
  final List<String> details;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('report-preview-pdf'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDDE3EC)),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D172B4D),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SMP NEGERI 1',
            style: TextStyle(
              color: Color(0xFF168B83),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'LAPORAN ${_sectionLabel(section).toUpperCase()}',
            key: const Key('report-preview-document-title'),
            style: const TextStyle(
              color: Color(0xFF172B4D),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Periode: $periodLabel',
            style: const TextStyle(color: Color(0xFF69778D), fontSize: 10),
          ),
          const Divider(height: 22),
          const Text(
            'RINGKASAN',
            style: TextStyle(
              color: Color(0xFF8994A7),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          ...summary.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      style: const TextStyle(
                        color: Color(0xFF53627A),
                        fontSize: 10,
                      ),
                    ),
                  ),
                  Text(
                    item.value,
                    style: const TextStyle(
                      color: Color(0xFF263752),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 22),
          const Text(
            'CONTOH RINCIAN',
            style: TextStyle(
              color: Color(0xFF8994A7),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          if (details.isEmpty)
            const Text(
              'Belum ada baris rincian pada filter ini.',
              key: Key('report-preview-pdf-empty'),
              style: TextStyle(color: Color(0xFF8994A7), fontSize: 10),
            )
          else
            ...details.map(
              (detail) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF53627A),
                    fontSize: 9,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          const Divider(height: 22),
          const Text(
            'CONTOH TAMPILAN PDF · BELUM MENJADI FILE',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFB77B27),
              fontSize: 8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CsvReportPreview extends StatelessWidget {
  const _CsvReportPreview({
    required this.content,
    required this.headers,
    required this.rowCount,
  });

  final String content;
  final List<String> headers;
  final int rowCount;

  @override
  Widget build(BuildContext context) {
    final visibleRowCount = rowCount < 8 ? rowCount : 8;
    return Container(
      key: const Key('report-preview-csv'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF172B4D),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CONTOH ISI CSV',
            style: TextStyle(
              color: Color(0xFF7DD5CB),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              content,
              key: const Key('report-preview-csv-content'),
              style: const TextStyle(
                color: Color(0xFFE6EDF7),
                fontFamily: 'monospace',
                fontSize: 10,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            rowCount == 0
                ? 'Header tetap ditampilkan; belum ada baris data.'
                : 'Kolom: ${headers.join(', ')} · menampilkan $visibleRowCount dari $rowCount baris.',
            style: const TextStyle(color: Color(0xFFB7C5D8), fontSize: 9),
          ),
          const SizedBox(height: 6),
          const Text(
            'CSV mengikuti pemisah koma; ekspor nyata belum aktif.',
            style: TextStyle(color: Color(0xFFB7C5D8), fontSize: 9),
          ),
        ],
      ),
    );
  }
}

String _sectionLabel(_ReportSection section) => switch (section) {
  _ReportSection.overview => 'Ringkasan',
  _ReportSection.inventory => 'Inventaris',
  _ReportSection.movements => 'Mutasi',
  _ReportSection.maintenance => 'Pemeliharaan',
};

String _periodLabel(_ReportPeriod period) => switch (period) {
  _ReportPeriod.all => 'Semua periode',
  _ReportPeriod.days30 => '30 hari terakhir',
  _ReportPeriod.days365 => '12 bulan terakhir',
};

String _formatQuantity(double quantity) {
  return quantity == quantity.roundToDouble()
      ? quantity.toStringAsFixed(0)
      : quantity.toString();
}

String _escapeCsv(String value) {
  if (!value.contains(',') &&
      !value.contains('"') &&
      !value.contains('\n') &&
      !value.contains('\r')) {
    return value;
  }
  return '"${value.replaceAll('"', '""')}"';
}

class _ReportMockupNotice extends StatelessWidget {
  const _ReportMockupNotice();

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
              'Ringkasan memakai data inventaris, mutasi, dan pemeliharaan '
              'dari server. Saldo stok dan nilai rupiah inventaris belum '
              'ditampilkan karena data harga perolehan belum lengkap.',
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

class _OverviewReport extends StatelessWidget {
  const _OverviewReport({
    required this.items,
    required this.movements,
    required this.maintenance,
    required this.needsAttention,
    required this.activeMaintenance,
  });

  final List<InventoryItem> items;
  final List<StockMovement> movements;
  final List<MaintenanceRecord> maintenance;
  final int needsAttention;
  final int activeMaintenance;

  @override
  Widget build(BuildContext context) {
    final postedMovements = movements
        .where((movement) => movement.status == MovementStatus.posted)
        .length;
    final sections = [
      _ReportMetricData(
        'Aset tercatat',
        items.length,
        Icons.inventory_2_outlined,
        const Color(0xFF168B83),
      ),
      _ReportMetricData(
        'Perlu perhatian',
        needsAttention,
        Icons.warning_amber_rounded,
        const Color(0xFFE59B3F),
      ),
      _ReportMetricData(
        'Mutasi diposting',
        postedMovements,
        Icons.swap_horiz_rounded,
        const Color(0xFF5677C8),
      ),
      _ReportMetricData(
        'Pemeliharaan aktif',
        activeMaintenance,
        Icons.home_repair_service_outlined,
        const Color(0xFF9B6BC3),
      ),
    ];
    final conditionCounts = _countBy(items, (item) => item.condition);
    final categories = _countBy(items, (item) => item.category);
    final latestActivities = <_ActivityData>[
      ...movements.map(
        (movement) => _ActivityData(
          title: movementTypeLabel(movement.type),
          subtitle:
              '${movement.movementNumber} · ${movementStatusLabel(movement.status)}',
          date: movement.createdAt,
          icon: Icons.swap_horiz_rounded,
          color: const Color(0xFF5677C8),
        ),
      ),
      ...maintenance.map(
        (record) => _ActivityData(
          title: record.assetName,
          subtitle: 'Pemeliharaan · ${maintenanceStatusLabel(record.status)}',
          date: record.reportedAt,
          icon: Icons.home_repair_service_outlined,
          color: const Color(0xFF9B6BC3),
        ),
      ),
    ]..sort((a, b) => b.date.compareTo(a.date));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReportMetricGrid(metrics: sections),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final conditionPanel = _ReportBreakdown(
              title: 'Kondisi aset',
              subtitle: '${items.length} aset pada hasil pencarian',
              values: _toBreakdownValues(conditionCounts),
              emptyMessage: 'Tidak ada data aset untuk ditampilkan.',
            );
            final categoryPanel = _ReportBreakdown(
              title: 'Kategori inventaris',
              subtitle: '${categories.length} kategori pada daftar lokal',
              values: _toBreakdownValues(categories),
              emptyMessage: 'Tidak ada data kategori untuk ditampilkan.',
            );
            if (constraints.maxWidth >= 900) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: conditionPanel),
                  const SizedBox(width: 14),
                  Expanded(child: categoryPanel),
                ],
              );
            }
            return Column(
              children: [
                conditionPanel,
                const SizedBox(height: 14),
                categoryPanel,
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _ActivityPanel(
          title: 'Aktivitas terbaru',
          activities: latestActivities.take(5).toList(),
          emptyMessage: 'Belum ada data mutasi atau pemeliharaan.',
        ),
      ],
    );
  }
}

class _InventoryReport extends StatelessWidget {
  const _InventoryReport({required this.items});

  final List<InventoryItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReportMetricGrid(
          metrics: [
            _ReportMetricData(
              'Aset pada laporan',
              items.length,
              Icons.inventory_2_outlined,
              const Color(0xFF168B83),
            ),
            _ReportMetricData(
              'Kondisi bagus',
              items.where((item) => item.condition == 'Bagus').length,
              Icons.check_circle_outline_rounded,
              const Color(0xFF42A786),
            ),
            _ReportMetricData(
              'Service',
              items.where((item) => item.condition == 'Dalam service').length,
              Icons.home_repair_service_outlined,
              const Color(0xFF5677C8),
            ),
            _ReportMetricData(
              'Rusak',
              items.where((item) => item.condition == 'Rusak').length,
              Icons.warning_amber_rounded,
              const Color(0xFFD26355),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _ReportBreakdown(
          title: 'Kondisi aset',
          subtitle: 'Jumlah unit per kondisi',
          values: _toBreakdownValues(_countBy(items, (item) => item.condition)),
          emptyMessage: 'Tidak ada data aset untuk ditampilkan.',
        ),
        const SizedBox(height: 14),
        _ReportBreakdown(
          title: 'Kategori',
          subtitle: 'Jumlah unit per kategori',
          values: _toBreakdownValues(_countBy(items, (item) => item.category)),
          emptyMessage: 'Tidak ada data kategori untuk ditampilkan.',
        ),
        const SizedBox(height: 14),
        _ReportBreakdown(
          title: 'Lokasi',
          subtitle: 'Jumlah unit per lokasi saat ini',
          values: _toBreakdownValues(_countBy(items, (item) => item.location)),
          emptyMessage: 'Tidak ada data lokasi untuk ditampilkan.',
        ),
      ],
    );
  }
}

class _MovementReport extends StatelessWidget {
  const _MovementReport({required this.movements});

  final List<StockMovement> movements;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReportMetricGrid(
          metrics: [
            _ReportMetricData(
              'Total mutasi',
              movements.length,
              Icons.swap_horiz_rounded,
              const Color(0xFF5677C8),
            ),
            _ReportMetricData(
              'Draft',
              movements
                  .where((movement) => movement.status == MovementStatus.draft)
                  .length,
              Icons.edit_note_rounded,
              const Color(0xFFE59B3F),
            ),
            _ReportMetricData(
              'Diposting',
              movements
                  .where((movement) => movement.status == MovementStatus.posted)
                  .length,
              Icons.check_circle_outline_rounded,
              const Color(0xFF42A786),
            ),
            _ReportMetricData(
              'Dibatalkan',
              movements
                  .where(
                    (movement) => movement.status == MovementStatus.cancelled,
                  )
                  .length,
              Icons.cancel_outlined,
              const Color(0xFF8994A7),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _ActivityPanel(
          title: 'Riwayat mutasi pada periode',
          activities: movements
              .map(
                (movement) => _ActivityData(
                  title: movement.movementNumber,
                  subtitle:
                      '${movementTypeLabel(movement.type)} · ${movementStatusLabel(movement.status)} · ${movement.lines.map((line) => line.itemName).join(', ')}',
                  date: movement.createdAt,
                  icon: Icons.swap_horiz_rounded,
                  color: const Color(0xFF5677C8),
                ),
              )
              .toList(),
          emptyMessage: 'Belum ada mutasi pada periode yang dipilih.',
        ),
      ],
    );
  }
}

class _MaintenanceReport extends StatelessWidget {
  const _MaintenanceReport({required this.records});

  final List<MaintenanceRecord> records;

  @override
  Widget build(BuildContext context) {
    final totalCost = records
        .where((record) => record.status == MaintenanceStatus.completed)
        .fold<double>(0, (total, record) => total + record.cost);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReportMetricGrid(
          metrics: [
            _ReportMetricData(
              'Total laporan',
              records.length,
              Icons.assignment_outlined,
              const Color(0xFF5677C8),
            ),
            _ReportMetricData(
              'Masih aktif',
              records
                  .where(
                    (record) =>
                        record.status == MaintenanceStatus.reported ||
                        record.status == MaintenanceStatus.inProgress,
                  )
                  .length,
              Icons.home_repair_service_outlined,
              const Color(0xFFE59B3F),
            ),
            _ReportMetricData(
              'Selesai',
              records
                  .where(
                    (record) => record.status == MaintenanceStatus.completed,
                  )
                  .length,
              Icons.check_circle_outline_rounded,
              const Color(0xFF42A786),
            ),
            _ReportMetricData(
              'Biaya selesai',
              _formatCurrency(totalCost),
              Icons.payments_outlined,
              const Color(0xFF9B6BC3),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _ActivityPanel(
          title: 'Riwayat pemeliharaan pada periode',
          activities: records
              .map(
                (record) => _ActivityData(
                  title: record.assetName,
                  subtitle:
                      '${record.assetCode} · ${maintenanceStatusLabel(record.status)} · ${_formatCurrency(record.cost)}',
                  date: record.reportedAt,
                  icon: Icons.home_repair_service_outlined,
                  color: const Color(0xFF9B6BC3),
                ),
              )
              .toList(),
          emptyMessage: 'Belum ada pemeliharaan pada periode yang dipilih.',
        ),
      ],
    );
  }
}

class _ReportMetricGrid extends StatelessWidget {
  const _ReportMetricGrid({required this.metrics});

  final List<_ReportMetricData> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: width,
                  child: _ReportMetricCard(metric: metric),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _ReportMetricData {
  const _ReportMetricData(this.label, this.value, this.icon, this.color);

  final String label;
  final Object value;
  final IconData icon;
  final Color color;
}

class _ReportMetricCard extends StatelessWidget {
  const _ReportMetricCard({required this.metric});

  final _ReportMetricData metric;

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
          Icon(metric.icon, color: metric.color, size: 22),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  metric.value.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

class _BreakdownValue {
  const _BreakdownValue(this.label, this.count);

  final String label;
  final int count;
}

class _ReportBreakdown extends StatelessWidget {
  const _ReportBreakdown({
    required this.title,
    required this.subtitle,
    required this.values,
    required this.emptyMessage,
  });

  final String title;
  final String subtitle;
  final List<_BreakdownValue> values;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final sortedValues = values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    final maxCount = sortedValues.isEmpty ? 1 : sortedValues.first.count;
    return _ReportPanel(
      title: title,
      subtitle: subtitle,
      child: sortedValues.isEmpty
          ? Text(emptyMessage, style: Theme.of(context).textTheme.bodySmall)
          : Column(
              children: sortedValues
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: Text(
                              entry.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: entry.count / maxCount,
                                minHeight: 8,
                                backgroundColor: const Color(0xFFF0F2F5),
                                color: const Color(0xFF168B83),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 24,
                            child: Text(
                              '${entry.count}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                color: Color(0xFF263752),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _ReportPanel extends StatelessWidget {
  const _ReportPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFEDF0F4)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _ActivityData {
  const _ActivityData({
    required this.title,
    required this.subtitle,
    required this.date,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final DateTime date;
  final IconData icon;
  final Color color;
}

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({
    required this.title,
    required this.activities,
    required this.emptyMessage,
  });

  final String title;
  final List<_ActivityData> activities;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return _ReportPanel(
      title: title,
      subtitle: '${activities.length} catatan pada hasil laporan',
      child: activities.isEmpty
          ? Text(
              emptyMessage,
              key: const Key('report-activity-empty'),
              style: Theme.of(context).textTheme.bodySmall,
            )
          : Column(
              children: activities
                  .map(
                    (activity) => Padding(
                      padding: const EdgeInsets.only(bottom: 13),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: activity.color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              activity.icon,
                              size: 18,
                              color: activity.color,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activity.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF263752),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  activity.subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDate(activity.date),
                            style: const TextStyle(
                              color: Color(0xFF8994A7),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _ReportSelector<T> extends StatelessWidget {
  const _ReportSelector({
    super.key,
    required this.value,
    required this.label,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final String label;
  final List<_ReportOption<T>> options;
  final ValueChanged<T> onChanged;

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
          hint: Text(label),
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
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

class _ReportOption<T> {
  const _ReportOption(this.value, this.label);

  final T value;
  final String label;
}

Map<String, int> _countBy<T>(Iterable<T> values, String Function(T) labelFor) {
  final counts = <String, int>{};
  for (final value in values) {
    final label = labelFor(value);
    counts.update(label, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts;
}

List<_BreakdownValue> _toBreakdownValues(Map<String, int> counts) {
  return counts.entries
      .map((entry) => _BreakdownValue(entry.key, entry.value))
      .toList();
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String _formatCurrency(double value) {
  final digits = value.toStringAsFixed(0);
  final grouped = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => '.',
  );
  return 'Rp $grouped';
}
