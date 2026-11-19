// CATATAN PEMELIHARAAN: layar ini menampilkan dua koleksi berbeda:
// item_kinds dan categories. Parent mengirim CRUD ke ApiClient; pertahankan
// form, validasi, serta field payload sesuai schema Mongo masing-masing.
import 'package:flutter/material.dart';

import '../models/master_data.dart';

class ItemKindsCategoriesPage extends StatefulWidget {
  const ItemKindsCategoriesPage({
    super.key,
    required this.itemKinds,
    required this.categories,
    required this.searchQuery,
    required this.onSaveKind,
    required this.onToggleKind,
    required this.onSaveCategory,
    required this.onToggleCategory,
    this.canEdit = true,
  });

  final List<ItemKind> itemKinds;
  final List<ItemCategory> categories;
  final String searchQuery;
  final ValueChanged<ItemKind> onSaveKind;
  final ValueChanged<ItemKind> onToggleKind;
  final ValueChanged<ItemCategory> onSaveCategory;
  final ValueChanged<ItemCategory> onToggleCategory;
  final bool canEdit;

  @override
  State<ItemKindsCategoriesPage> createState() =>
      _ItemKindsCategoriesPageState();
}

class _ItemKindsCategoriesPageState extends State<ItemKindsCategoriesPage> {
  int _selectedTab = 0;

  Future<void> _openKindDialog([ItemKind? itemKind]) async {
    final result = await showDialog<ItemKind>(
      context: context,
      builder: (context) =>
          ItemKindDialog(itemKinds: widget.itemKinds, itemKind: itemKind),
    );
    if (result != null && mounted) widget.onSaveKind(result);
  }

  Future<void> _openCategoryDialog([ItemCategory? category]) async {
    final result = await showDialog<ItemCategory>(
      context: context,
      builder: (context) =>
          ItemCategoryDialog(categories: widget.categories, category: category),
    );
    if (result != null && mounted) widget.onSaveCategory(result);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Jenis & Kategori',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          widget.canEdit
              ? 'Atur jenis barang dan kategori untuk pengelompokan aset.'
              : 'Lihat jenis barang dan kategori untuk pengelompokan aset.',
        ),
        const SizedBox(height: 16),
        const _CatalogNote(),
        const SizedBox(height: 16),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 0,
              icon: Icon(Icons.inventory_2_outlined),
              label: Text('Jenis Barang'),
            ),
            ButtonSegment(
              value: 1,
              icon: Icon(Icons.category_outlined),
              label: Text('Kategori'),
            ),
          ],
          selected: {_selectedTab},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            setState(() => _selectedTab = selection.first);
          },
        ),
        const SizedBox(height: 16),
        if (_selectedTab == 0)
          _ItemKindSection(
            itemKinds: widget.itemKinds,
            searchQuery: widget.searchQuery,
            canEdit: widget.canEdit,
            onAdd: () => _openKindDialog(),
            onEdit: _openKindDialog,
            onToggle: widget.onToggleKind,
          )
        else
          _CategorySection(
            categories: widget.categories,
            searchQuery: widget.searchQuery,
            canEdit: widget.canEdit,
            onAdd: () => _openCategoryDialog(),
            onEdit: _openCategoryDialog,
            onToggle: widget.onToggleCategory,
          ),
      ],
    );
  }
}

/// Form jenis barang; hanya mengembalikan nilai, penyimpanan dikelola parent.
class ItemKindDialog extends StatefulWidget {
  const ItemKindDialog({super.key, required this.itemKinds, this.itemKind});

  final List<ItemKind> itemKinds;
  final ItemKind? itemKind;

  @override
  State<ItemKindDialog> createState() => _ItemKindDialogState();
}

class _ItemKindDialogState extends State<ItemKindDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.itemKind?.code ?? '');
    _nameController = TextEditingController(text: widget.itemKind?.name ?? '');
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      ItemKind(
        id:
            widget.itemKind?.id ??
            'kind-${DateTime.now().microsecondsSinceEpoch}',
        code: _codeController.text.trim().toUpperCase(),
        name: _nameController.text.trim(),
        isActive: widget.itemKind?.isActive ?? true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.itemKind == null ? 'Tambah Jenis Barang' : 'Ubah Jenis',
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _UniqueCodeField(
                key: const Key('kind-code-input'),
                controller: _codeController,
                label: 'Kode jenis',
                exists: (code) => widget.itemKinds.any(
                  (entry) =>
                      entry.id != widget.itemKind?.id &&
                      entry.code.toLowerCase() == code.toLowerCase(),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('kind-name-input'),
                controller: _nameController,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Nama jenis'),
                validator: _requiredName,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const Key('save-kind'),
          onPressed: _submit,
          child: const Text('Simpan jenis'),
        ),
      ],
    );
  }
}

/// Form kategori; deskripsi bersifat opsional sesuai skema koleksi categories.
class ItemCategoryDialog extends StatefulWidget {
  const ItemCategoryDialog({
    super.key,
    required this.categories,
    this.category,
  });

  final List<ItemCategory> categories;
  final ItemCategory? category;

  @override
  State<ItemCategoryDialog> createState() => _ItemCategoryDialogState();
}

class _ItemCategoryDialogState extends State<ItemCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.category?.code ?? '');
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _descriptionController = TextEditingController(
      text: widget.category?.description ?? '',
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      ItemCategory(
        id:
            widget.category?.id ??
            'cat-${DateTime.now().microsecondsSinceEpoch}',
        code: _codeController.text.trim().toUpperCase(),
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        isActive: widget.category?.isActive ?? true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.category == null ? 'Tambah Kategori' : 'Ubah Kategori',
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _UniqueCodeField(
                  key: const Key('category-code-input'),
                  controller: _codeController,
                  label: 'Kode kategori',
                  exists: (code) => widget.categories.any(
                    (entry) =>
                        entry.id != widget.category?.id &&
                        entry.code.toLowerCase() == code.toLowerCase(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('category-name-input'),
                  controller: _nameController,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Nama kategori'),
                  validator: _requiredName,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('category-description-input'),
                  controller: _descriptionController,
                  maxLength: 2000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Deskripsi (opsional)',
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
          key: const Key('save-category'),
          onPressed: _submit,
          child: const Text('Simpan kategori'),
        ),
      ],
    );
  }
}

class _UniqueCodeField extends StatelessWidget {
  const _UniqueCodeField({
    super.key,
    required this.controller,
    required this.label,
    required this.exists,
  });

  final TextEditingController controller;
  final String label;
  final bool Function(String) exists;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLength: 64,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final code = value?.trim() ?? '';
        if (code.isEmpty) return '$label wajib diisi';
        if (exists(code)) return '$label sudah digunakan';
        return null;
      },
    );
  }
}

String? _requiredName(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return 'Nama wajib diisi';
  if (name.length > 120) return 'Maksimal 120 karakter';
  return null;
}

class _ItemKindSection extends StatelessWidget {
  const _ItemKindSection({
    required this.itemKinds,
    required this.searchQuery,
    required this.canEdit,
    required this.onAdd,
    required this.onEdit,
    required this.onToggle,
  });

  final List<ItemKind> itemKinds;
  final String searchQuery;
  final bool canEdit;
  final VoidCallback onAdd;
  final ValueChanged<ItemKind> onEdit;
  final ValueChanged<ItemKind> onToggle;

  @override
  Widget build(BuildContext context) {
    final query = searchQuery.trim().toLowerCase();
    final entries = itemKinds
        .where(
          (item) =>
              item.name.toLowerCase().contains(query) ||
              item.code.toLowerCase().contains(query),
        )
        .toList();

    return _MasterListPanel(
      title: 'Daftar Jenis Barang',
      count: entries.length,
      addLabel: 'Tambah Jenis',
      onAdd: onAdd,
      canEdit: canEdit,
      isEmpty: entries.isEmpty,
      emptyMessage: 'Jenis barang tidak ditemukan.',
      contentBuilder: (context, isCompact) {
        if (isCompact) {
          return Column(
            children: entries
                .map(
                  (entry) => _MasterCard(
                    title: entry.name,
                    code: entry.code,
                    subtitle: null,
                    isActive: entry.isActive,
                    canEdit: canEdit,
                    onEdit: () => onEdit(entry),
                    onToggle: () => onToggle(entry),
                    editLabel: 'Ubah jenis',
                  ),
                )
                .toList(),
          );
        }
        return DataTable(
          columns: [
            DataColumn(label: Text('KODE')),
            DataColumn(label: Text('NAMA JENIS')),
            DataColumn(label: Text('STATUS')),
            if (canEdit) const DataColumn(label: Text('AKSI')),
          ],
          rows: entries
              .map(
                (entry) => DataRow(
                  cells: [
                    DataCell(Text(entry.code)),
                    DataCell(Text(entry.name)),
                    DataCell(_MasterStatus(isActive: entry.isActive)),
                    if (canEdit)
                      DataCell(
                        _MasterActions(
                          isActive: entry.isActive,
                          editLabel: 'Ubah jenis',
                          onEdit: () => onEdit(entry),
                          onToggle: () => onToggle(entry),
                        ),
                      ),
                  ],
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.categories,
    required this.searchQuery,
    required this.canEdit,
    required this.onAdd,
    required this.onEdit,
    required this.onToggle,
  });

  final List<ItemCategory> categories;
  final String searchQuery;
  final bool canEdit;
  final VoidCallback onAdd;
  final ValueChanged<ItemCategory> onEdit;
  final ValueChanged<ItemCategory> onToggle;

  @override
  Widget build(BuildContext context) {
    final query = searchQuery.trim().toLowerCase();
    final entries = categories
        .where(
          (item) =>
              item.name.toLowerCase().contains(query) ||
              item.code.toLowerCase().contains(query) ||
              item.description.toLowerCase().contains(query),
        )
        .toList();

    return _MasterListPanel(
      title: 'Daftar Kategori',
      count: entries.length,
      addLabel: 'Tambah Kategori',
      onAdd: onAdd,
      canEdit: canEdit,
      isEmpty: entries.isEmpty,
      emptyMessage: 'Kategori tidak ditemukan.',
      contentBuilder: (context, isCompact) {
        if (isCompact) {
          return Column(
            children: entries
                .map(
                  (entry) => _MasterCard(
                    title: entry.name,
                    code: entry.code,
                    subtitle: entry.description,
                    isActive: entry.isActive,
                    canEdit: canEdit,
                    onEdit: () => onEdit(entry),
                    onToggle: () => onToggle(entry),
                    editLabel: 'Ubah kategori',
                  ),
                )
                .toList(),
          );
        }
        return DataTable(
          columns: [
            DataColumn(label: Text('KODE')),
            DataColumn(label: Text('NAMA KATEGORI')),
            DataColumn(label: Text('DESKRIPSI')),
            DataColumn(label: Text('STATUS')),
            if (canEdit) const DataColumn(label: Text('AKSI')),
          ],
          rows: entries
              .map(
                (entry) => DataRow(
                  cells: [
                    DataCell(Text(entry.code)),
                    DataCell(Text(entry.name)),
                    DataCell(
                      SizedBox(
                        width: 300,
                        child: Text(
                          entry.description.isEmpty ? '-' : entry.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(_MasterStatus(isActive: entry.isActive)),
                    if (canEdit)
                      DataCell(
                        _MasterActions(
                          isActive: entry.isActive,
                          editLabel: 'Ubah kategori',
                          onEdit: () => onEdit(entry),
                          onToggle: () => onToggle(entry),
                        ),
                      ),
                  ],
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _MasterListPanel extends StatelessWidget {
  const _MasterListPanel({
    required this.title,
    required this.count,
    required this.addLabel,
    required this.onAdd,
    required this.canEdit,
    required this.isEmpty,
    required this.emptyMessage,
    required this.contentBuilder,
  });

  final String title;
  final int count;
  final String addLabel;
  final VoidCallback onAdd;
  final bool canEdit;
  final bool isEmpty;
  final String emptyMessage;
  final Widget Function(BuildContext, bool) contentBuilder;

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
              final compact = constraints.maxWidth < 650;
              final heading = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    '$count data ditampilkan',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              );
              final addButton = FilledButton.icon(
                key: const Key('create-master-entry'),
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(addLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF168B83),
                ),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading,
                    if (canEdit) ...[const SizedBox(height: 12), addButton],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: heading),
                  if (canEdit) addButton,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          if (isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(child: Text(emptyMessage)),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 740;
                if (compact) return contentBuilder(context, true);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: contentBuilder(context, false),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _MasterCard extends StatelessWidget {
  const _MasterCard({
    required this.title,
    required this.code,
    required this.subtitle,
    required this.isActive,
    required this.canEdit,
    required this.onEdit,
    required this.onToggle,
    required this.editLabel,
  });

  final String title;
  final String code;
  final String? subtitle;
  final bool isActive;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final String editLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
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
                  title,
                  style: const TextStyle(
                    color: Color(0xFF263752),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (canEdit)
                _MasterActions(
                  isActive: isActive,
                  editLabel: editLabel,
                  onEdit: onEdit,
                  onToggle: onToggle,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(code, style: Theme.of(context).textTheme.bodySmall),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          _MasterStatus(isActive: isActive),
        ],
      ),
    );
  }
}

class _MasterStatus extends StatelessWidget {
  const _MasterStatus({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? const Color(0xFF368A6C) : const Color(0xFF8994A7);
    return Text(
      isActive ? 'Aktif' : 'Nonaktif',
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
    );
  }
}

class _MasterActions extends StatelessWidget {
  const _MasterActions({
    required this.isActive,
    required this.editLabel,
    required this.onEdit,
    required this.onToggle,
  });

  final bool isActive;
  final String editLabel;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (action) {
        if (action == 'edit') onEdit();
        if (action == 'toggle') onToggle();
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.edit_outlined, size: 18),
            title: Text(editLabel),
          ),
        ),
        PopupMenuItem(
          value: 'toggle',
          child: ListTile(
            dense: true,
            leading: Icon(
              isActive ? Icons.archive_outlined : Icons.unarchive_outlined,
              size: 18,
            ),
            title: Text(isActive ? 'Nonaktifkan (arsip)' : 'Aktifkan kembali'),
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

class _CatalogNote extends StatelessWidget {
  const _CatalogNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4F3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'Jenis barang dan kategori disimpan pada koleksi terpisah. Arsip tidak menghapus data atau memutus referensi barang yang sudah terdaftar.',
        style: TextStyle(color: Color(0xFF4F6D6A), fontSize: 11, height: 1.45),
      ),
    );
  }
}
