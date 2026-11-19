// CATATAN PEMELIHARAAN: halaman ini mengelola struktur lokasi induk-anak.
// Pencarian mencakup kode/nama/jenis/induk; field model mengikuti koleksi
// locations. Simpan perubahan lewat callback agar state tetap dimiliki parent.
import 'package:flutter/material.dart';

import '../models/master_data.dart';

class LocationsPage extends StatefulWidget {
  const LocationsPage({
    super.key,
    required this.locations,
    required this.searchQuery,
    required this.onSave,
    required this.onToggleActive,
    this.canEdit = true,
  });

  final List<MasterLocation> locations;
  final String searchQuery;
  final ValueChanged<MasterLocation> onSave;
  final ValueChanged<MasterLocation> onToggleActive;
  final bool canEdit;

  @override
  State<LocationsPage> createState() => _LocationsPageState();
}

class _LocationsPageState extends State<LocationsPage> {
  List<MasterLocation> get _filteredLocations {
    final query = widget.searchQuery.trim().toLowerCase();
    return widget.locations.where((location) {
      final parentName = _parentName(location.parentId).toLowerCase();
      return query.isEmpty ||
          location.code.toLowerCase().contains(query) ||
          location.name.toLowerCase().contains(query) ||
          _locationTypeLabel(location.locationType)
              .toLowerCase()
              .contains(query) ||
          parentName.contains(query);
    }).toList();
  }

  String _parentName(String? parentId) {
    if (parentId == null) return 'Lokasi utama';
    for (final location in widget.locations) {
      if (location.id == parentId) return location.name;
    }
    return 'Induk tidak ditemukan';
  }

  Future<void> _openForm([MasterLocation? location]) async {
    final result = await showDialog<MasterLocation>(
      context: context,
      builder: (context) =>
          LocationDialog(locations: widget.locations, location: location),
    );
    if (result != null && mounted) widget.onSave(result);
  }

  @override
  Widget build(BuildContext context) {
    final filteredLocations = _filteredLocations;
    final activeCount = widget.locations.where((item) => item.isActive).length;

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
                  'Lokasi',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  widget.canEdit
                      ? 'Atur sekolah, gedung, ruang, gudang, dan area.'
                      : 'Lihat struktur sekolah, gedung, ruang, gudang, dan area.',
                ),
              ],
            );
            final addButton = FilledButton.icon(
              key: const Key('create-location'),
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add_location_alt_outlined, size: 18),
              label: const Text('Tambah Lokasi'),
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
                  if (widget.canEdit) ...[
                    const SizedBox(height: 16),
                    addButton,
                  ],
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: heading),
                if (widget.canEdit) addButton,
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        const _LocationNote(),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _LocationMetric(
              label: 'Total lokasi',
              value: widget.locations.length,
              icon: Icons.location_on_outlined,
              color: const Color(0xFF5677C8),
            ),
            _LocationMetric(
              label: 'Lokasi aktif',
              value: activeCount,
              icon: Icons.place_outlined,
              color: const Color(0xFF168B83),
            ),
            _LocationMetric(
              label: 'Nonaktif',
              value: widget.locations.length - activeCount,
              icon: Icons.location_off_outlined,
              color: const Color(0xFFE59B3F),
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
              Text(
                '${filteredLocations.length} lokasi ditemukan',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              if (filteredLocations.isEmpty)
                const _EmptyLocations()
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 740) {
                      return Column(
                        children: filteredLocations
                            .map(
                              (location) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _LocationCard(
                                  location: location,
                                  parentName: _parentName(location.parentId),
                                  canEdit: widget.canEdit,
                                  onEdit: widget.canEdit
                                      ? () => _openForm(location)
                                      : null,
                                  onToggleActive: widget.canEdit
                                      ? () => widget.onToggleActive(location)
                                      : null,
                                ),
                              ),
                            )
                            .toList(),
                      );
                    }
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: DataTable(
                          headingRowColor: const WidgetStatePropertyAll(
                            Color(0xFFF8FAFC),
                          ),
                          columns: [
                            const DataColumn(label: Text('KODE')),
                            const DataColumn(label: Text('NAMA LOKASI')),
                            const DataColumn(label: Text('JENIS')),
                            const DataColumn(label: Text('LOKASI INDUK')),
                            const DataColumn(label: Text('STATUS')),
                            if (widget.canEdit)
                              const DataColumn(label: Text('AKSI')),
                          ],
                          rows: filteredLocations
                              .map(
                                (location) => DataRow(
                                  cells: [
                                    DataCell(Text(location.code)),
                                    DataCell(
                                      Text(
                                        location.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        _locationTypeLabel(
                                          location.locationType,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(_parentName(location.parentId)),
                                    ),
                                    DataCell(
                                      _LocationStatus(
                                        isActive: location.isActive,
                                      ),
                                    ),
                                    if (widget.canEdit)
                                      DataCell(
                                        _LocationActions(
                                          location: location,
                                          onEdit: () => _openForm(location),
                                          onToggleActive: () =>
                                              widget.onToggleActive(location),
                                        ),
                                      ),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Form lokasi mengembalikan input ke parent untuk disimpan melalui API.
///
/// CATATAN PEMELIHARAAN: pilihan induk mencegah lokasi menjadi induknya sendiri
/// atau turunannya sebagai bantuan UX; backend tetap memvalidasi referensi,
/// siklus, status induk, dan kode unik sebelum mengubah MongoDB.
class LocationDialog extends StatefulWidget {
  const LocationDialog({super.key, required this.locations, this.location});

  final List<MasterLocation> locations;
  final MasterLocation? location;

  @override
  State<LocationDialog> createState() => _LocationDialogState();
}

class _LocationDialogState extends State<LocationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late String _locationType;
  late String _parentId;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.location?.code ?? '');
    _nameController = TextEditingController(text: widget.location?.name ?? '');
    _locationType = widget.location?.locationType ?? 'ruang';
    _parentId = widget.location?.parentId ?? '';
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Set<String> _excludedParentIds() {
    final locationId = widget.location?.id;
    if (locationId == null) return const {};

    final excluded = <String>{locationId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final location in widget.locations) {
        if (location.parentId != null &&
            excluded.contains(location.parentId) &&
            excluded.add(location.id)) {
          changed = true;
        }
      }
    }
    return excluded;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final current = widget.location;
    Navigator.of(context).pop(
      MasterLocation(
        id: current?.id ?? 'loc-${DateTime.now().microsecondsSinceEpoch}',
        code: _codeController.text.trim().toUpperCase(),
        name: _nameController.text.trim(),
        locationType: _locationType,
        parentId: _parentId.isEmpty ? null : _parentId,
        isActive: current?.isActive ?? true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final excludedParentIds = _excludedParentIds();
    final parents = widget.locations
        .where(
          (location) =>
              !excludedParentIds.contains(location.id) &&
              (location.isActive || location.id == widget.location?.parentId),
        )
        .toList();

    return AlertDialog(
      title: Text(widget.location == null ? 'Tambah Lokasi' : 'Ubah Lokasi'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('location-code-input'),
                  controller: _codeController,
                  decoration: const InputDecoration(labelText: 'Kode lokasi'),
                  validator: (value) {
                    final code = value?.trim() ?? '';
                    if (code.isEmpty) return 'Kode lokasi wajib diisi';
                    if (code.length > 64) return 'Maksimal 64 karakter';
                    final duplicate = widget.locations.any(
                      (location) =>
                          location.id != widget.location?.id &&
                          location.code.toLowerCase() == code.toLowerCase(),
                    );
                    return duplicate ? 'Kode lokasi sudah digunakan' : null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('location-name-input'),
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nama lokasi'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Nama lokasi wajib diisi'
                      : value.trim().length > 200
                      ? 'Maksimal 200 karakter'
                      : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  key: const Key('location-type-input'),
                  initialValue: _locationType,
                  decoration: const InputDecoration(labelText: 'Jenis lokasi'),
                  items: _locationTypes
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(_locationTypeLabel(type)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _locationType = value);
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  key: const Key('location-parent-input'),
                  initialValue: _parentId,
                  decoration: const InputDecoration(
                    labelText: 'Lokasi induk (opsional)',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Tidak ada induk'),
                    ),
                    ...parents.map(
                      (parent) => DropdownMenuItem(
                        value: parent.id,
                        child: Text(parent.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _parentId = value);
                  },
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Perubahan disimpan ke server setelah Anda menekan Simpan lokasi.',
                    style: TextStyle(
                      color: Color(0xFF69778D),
                      fontSize: 11,
                      height: 1.4,
                    ),
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
          key: const Key('save-location'),
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF168B83),
          ),
          child: const Text('Simpan lokasi'),
        ),
      ],
    );
  }
}

const _locationTypes = [
  'sekolah',
  'gedung',
  'ruang',
  'gudang',
  'area',
  'lainnya',
];

String _locationTypeLabel(String value) => switch (value) {
  'sekolah' => 'Sekolah',
  'gedung' => 'Gedung',
  'ruang' => 'Ruang',
  'gudang' => 'Gudang',
  'area' => 'Area',
  _ => 'Lainnya',
};

class _LocationNote extends StatelessWidget {
  const _LocationNote();

  @override
  Widget build(BuildContext context) {
    return const _InfoNote(
      text: 'Lokasi tersimpan di server. Pilih induk aktif untuk membentuk struktur; lokasi dengan turunan aktif harus diarsipkan dari tingkat paling bawah.',
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4F3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF168B83),
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF4F6D6A),
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

class _LocationMetric extends StatelessWidget {
  const _LocationMetric({
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
      width: 190,
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

class _LocationStatus extends StatelessWidget {
  const _LocationStatus({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? const Color(0xFF368A6C) : const Color(0xFF8994A7);
    return Text(
      isActive ? 'Aktif' : 'Nonaktif',
      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11),
    );
  }
}

class _LocationActions extends StatelessWidget {
  const _LocationActions({
    required this.location,
    required this.onEdit,
    required this.onToggleActive,
  });

  final MasterLocation location;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Aksi ${location.name}',
      onSelected: (action) {
        if (action == 'edit') onEdit();
        if (action == 'toggle') onToggleActive();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.edit_outlined, size: 18),
            title: Text('Ubah lokasi'),
          ),
        ),
        PopupMenuItem(
          value: 'toggle',
          child: ListTile(
            dense: true,
            leading: Icon(
              location.isActive ? Icons.location_off_outlined : Icons.place,
              size: 18,
            ),
            title: Text(
              location.isActive ? 'Nonaktifkan (arsip)' : 'Aktifkan kembali',
            ),
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

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.location,
    required this.parentName,
    required this.canEdit,
    required this.onEdit,
    required this.onToggleActive,
  });

  final MasterLocation location;
  final String parentName;
  final bool canEdit;
  final VoidCallback? onEdit;
  final VoidCallback? onToggleActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
                  location.name,
                  style: const TextStyle(
                    color: Color(0xFF263752),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (canEdit)
                _LocationActions(
                  location: location,
                  onEdit: onEdit!,
                  onToggleActive: onToggleActive!,
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${location.code} · ${_locationTypeLabel(location.locationType)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 7),
          Text(
            'Induk: $parentName',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 7),
          _LocationStatus(isActive: location.isActive),
        ],
      ),
    );
  }
}

class _EmptyLocations extends StatelessWidget {
  const _EmptyLocations();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 30),
      child: Center(child: Text('Lokasi tidak ditemukan')),
    );
  }
}
