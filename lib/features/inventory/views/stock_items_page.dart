import 'package:flutter/material.dart';

import '../../master_data/models/master_data.dart';
import '../models/stock_item.dart';

/// Tab stok menampilkan saldo terpisah per lokasi dan batas minimum item.
/// CATATAN PEMELIHARAAN: penyimpanan hanya membuat katalog stok dan saldo
/// pembuka; pergerakan sesudahnya harus lewat endpoint mutasi/posting stok.
class StockItemsPage extends StatelessWidget {
  const StockItemsPage({
    super.key,
    required this.items,
    required this.locations,
    required this.categories,
    required this.kinds,
    required this.searchQuery,
    required this.canManage,
    required this.onCreate,
    required this.onEdit,
    required this.isLoading,
    required this.loadError,
    required this.onRetry,
  });

  final List<StockItem> items;
  final List<MasterLocation> locations;
  final List<ItemCategory> categories;
  final List<ItemKind> kinds;
  final String searchQuery;
  final bool canManage;
  final ValueChanged<StockItemInput> onCreate;
  final ValueChanged<StockItemEditInput> onEdit;
  final bool isLoading;
  final String? loadError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final query = searchQuery.trim().toLowerCase();
    final visible = items
        .where(
          (item) =>
              query.isEmpty ||
              item.name.toLowerCase().contains(query) ||
              item.code.toLowerCase().contains(query) ||
              item.category.toLowerCase().contains(query) ||
              item.balances.any(
                (row) => row.location.toLowerCase().contains(query),
              ),
        )
        .toList();
    final lowStock = items.where((item) => item.belowMinimum).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Barang Habis Pakai',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (canManage)
              FilledButton.icon(
                key: const Key('inventory-create-stock-item'),
                onPressed: () => _openCreate(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Tambah Barang Habis Pakai'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text('${items.length} barang · $lowStock di bawah batas minimum'),
        const SizedBox(height: 16),
        if (loadError != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(child: Text(loadError!)),
                  if (onRetry != null)
                    TextButton(
                      onPressed: onRetry,
                      child: const Text('Coba lagi'),
                    ),
                ],
              ),
            ),
          )
        else if (isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else
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
                Text('Daftar Barang', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('${visible.length} barang ditampilkan · $lowStock di bawah batas minimum', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 14),
                if (visible.isEmpty)
                  const _EmptyStockItems()
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 700) {
                        return Column(
                          children: visible.map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _StockItemCard(item: item, canEdit: canManage, onEdit: () => _openEdit(context, item)),
                          )).toList(),
                        );
                      }
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: constraints.maxWidth),
                            child: DataTable(
                              headingRowColor: const WidgetStatePropertyAll(Color(0xFFF8FAFC)),
                              headingTextStyle: const TextStyle(color: Color(0xFF8994A7), fontSize: 10, fontWeight: FontWeight.w600),
                              dataTextStyle: const TextStyle(color: Color(0xFF53627A), fontSize: 11),
                              columns: const [
                                DataColumn(label: Text('KODE')),
                                DataColumn(label: Text('NAMA BARANG')),
                                DataColumn(label: Text('KATEGORI')),
                                DataColumn(label: Text('LOKASI')),
                                DataColumn(label: Text('SALDO')),
                                DataColumn(label: Text('BATAS MINIMUM')),
                                DataColumn(label: Text('AKSI')),
                              ],
                              rows: visible.map((item) => DataRow(cells: [
                                DataCell(Text(item.code)),
                                DataCell(Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                                DataCell(Text(item.category)),
                                DataCell(Text(item.balances.map((b) => '${b.location}: ${_formatQuantity(b.quantity)} ${item.unit}').join(' · '))),
                                DataCell(Text('${_formatQuantity(item.total)} ${item.unit}')),
                                DataCell(Text('Minimum ${_formatQuantity(item.minimumStock)}', style: TextStyle(color: item.belowMinimum ? Colors.deepOrange : const Color(0xFF53627A)))),
                                DataCell(canManage ? TextButton.icon(
                                  key: Key('edit-stock-${item.itemId}'),
                                  onPressed: () => _openEdit(context, item),
                                  icon: const Icon(Icons.edit_outlined, size: 16),
                                  label: const Text('Edit'),
                                ) : const SizedBox.shrink()),
                              ])).toList(),
                            ),
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

  Future<void> _openCreate(BuildContext context) async {
    final result = await showDialog<StockItemInput>(
      context: context,
      builder: (context) => _CreateStockItemDialog(
        locations: locations.where((value) => value.isActive).toList(),
        categories: categories.where((value) => value.isActive).toList(),
        kinds: kinds
            .where(
              (value) =>
                  value.isActive &&
                  value.code.toLowerCase().replaceAll('-', '_') ==
                      'habis_pakai',
            )
            .toList(),
      ),
    );
    if (result != null) onCreate(result);
  }

  Future<void> _openEdit(BuildContext context, StockItem item) async {
    final result = await showDialog<StockItemEditInput>(
      context: context,
      builder: (context) => _EditStockItemDialog(
        item: item,
        locations: locations
            .where(
              (value) =>
                  value.isActive &&
                  item.balances.any(
                    (balance) => balance.locationId == value.id,
                  ),
            )
            .toList(),
        categories: categories.where((value) => value.isActive).toList(),
      ),
    );
    if (result != null) onEdit(result);
  }
}

class _StockItemCard extends StatelessWidget {
  const _StockItemCard({
    required this.item,
    required this.canEdit,
    required this.onEdit,
  });
  final StockItem item;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: const Color(0xFFFCFDFE),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: const Color(0xFFEDF0F4)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text('${item.code} · ${item.category} · ${item.unit}'),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_formatQuantity(item.total)} ${item.unit}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    item.belowMinimum
                        ? 'Di bawah minimum ${_formatQuantity(item.minimumStock)}'
                        : 'Minimum ${_formatQuantity(item.minimumStock)}',
                    style: TextStyle(
                      color: item.belowMinimum
                          ? Colors.deepOrange
                          : Colors.blueGrey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (item.balances.isNotEmpty) ...[
            const Divider(height: 22),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: item.balances
                  .map(
                    (row) => Chip(
                      avatar: const Icon(Icons.location_on_outlined, size: 16),
                      label: Text(
                        '${row.location}: ${_formatQuantity(row.quantity)} ${item.unit}',
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (canEdit)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: Key('edit-stock-${item.itemId}'),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit barang / jumlah'),
              ),
            ),
        ],
      ),
    ),
  );
}

class _EditStockItemDialog extends StatefulWidget {
  const _EditStockItemDialog({
    required this.item,
    required this.locations,
    required this.categories,
  });
  final StockItem item;
  final List<MasterLocation> locations;
  final List<ItemCategory> categories;

  @override
  State<_EditStockItemDialog> createState() => _EditStockItemDialogState();
}

class _EditStockItemDialogState extends State<_EditStockItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _unit;
  late final TextEditingController _minimum;
  late final TextEditingController _quantity;
  final _notes = TextEditingController();
  late String? _categoryId;
  late String? _locationId;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _name = TextEditingController(text: item.name);
    _unit = TextEditingController(text: item.unit);
    _minimum = TextEditingController(text: _formatQuantity(item.minimumStock));
    final balance = item.balances.firstOrNull;
    _quantity = TextEditingController(
      text: balance == null ? '0' : _formatQuantity(balance.quantity),
    );
    _categoryId = widget.categories.any((value) => value.id == item.categoryId)
        ? item.categoryId
        : widget.categories.firstOrNull?.id;
    _locationId = balance?.locationId;
  }

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _minimum.dispose();
    _quantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _nonNegative(String? value) {
    final number = double.tryParse(value ?? '');
    return number == null || number < 0 || !number.isFinite
        ? 'Masukkan angka nol atau lebih'
        : null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final categoryId = _categoryId;
    final locationId = _locationId;
    if (categoryId == null || locationId == null) return;
    Navigator.pop(
      context,
      StockItemEditInput(
        itemId: widget.item.itemId,
        name: _name.text.trim(),
        categoryId: categoryId,
        unit: _unit.text.trim(),
        minimumStock: double.parse(_minimum.text),
        locationId: locationId,
        quantity: double.parse(_quantity.text),
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Edit ${widget.item.name}'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('edit-stock-name'),
                controller: _name,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Nama barang'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null,
              ),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: widget.categories
                    .map(
                      (value) => DropdownMenuItem(
                        value: value.id,
                        child: Text(
                          value.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _categoryId = value),
                validator: (value) => value == null ? 'Pilih kategori' : null,
              ),
              TextFormField(
                key: const Key('edit-stock-unit'),
                controller: _unit,
                maxLength: 32,
                decoration: const InputDecoration(labelText: 'Satuan'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Satuan wajib diisi' : null,
              ),
              TextFormField(
                key: const Key('edit-stock-minimum'),
                controller: _minimum,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Batas minimum'),
                validator: _nonNegative,
              ),
              DropdownButtonFormField<String>(
                key: const Key('edit-stock-location'),
                isExpanded: true,
                initialValue: _locationId,
                decoration: const InputDecoration(
                  labelText: 'Lokasi yang dikoreksi',
                ),
                items: widget.locations
                    .map(
                      (value) => DropdownMenuItem(
                        value: value.id,
                        child: Text(
                          value.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _locationId = value),
                validator: (value) => value == null ? 'Pilih lokasi' : null,
              ),
              TextFormField(
                key: const Key('edit-stock-quantity'),
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Jumlah ${widget.item.unit} di lokasi ini',
                ),
                validator: _nonNegative,
              ),
              TextFormField(
                key: const Key('edit-stock-notes'),
                controller: _notes,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Alasan koreksi jumlah',
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Alasan koreksi wajib diisi'
                    : null,
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
        onPressed: widget.categories.isEmpty || widget.locations.isEmpty
            ? null
            : _submit,
        child: const Text('Simpan perubahan'),
      ),
    ],
  );
}

class _CreateStockItemDialog extends StatefulWidget {
  const _CreateStockItemDialog({
    required this.locations,
    required this.categories,
    required this.kinds,
  });
  final List<MasterLocation> locations;
  final List<ItemCategory> categories;
  final List<ItemKind> kinds;

  @override
  State<_CreateStockItemDialog> createState() => _CreateStockItemDialogState();
}

class _CreateStockItemDialogState extends State<_CreateStockItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _unit = TextEditingController(text: 'pcs');
  final _minimum = TextEditingController(text: '0');
  final _quantity = TextEditingController(text: '0');
  String? _kindId;
  String? _categoryId;
  String? _locationId;

  @override
  void initState() {
    super.initState();
    _kindId = widget.kinds.firstOrNull?.id;
    _categoryId = widget.categories.firstOrNull?.id;
    _locationId = widget.locations.firstOrNull?.id;
  }

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _minimum.dispose();
    _quantity.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final kindId = _kindId;
    final categoryId = _categoryId;
    final locationId = _locationId;
    if (kindId == null || categoryId == null || locationId == null) return;
    Navigator.pop(
      context,
      StockItemInput(
        name: _name.text.trim(),
        kindId: kindId,
        categoryId: categoryId,
        unit: _unit.text.trim(),
        minimumStock: double.parse(_minimum.text),
        locationId: locationId,
        initialQuantity: double.parse(_quantity.text),
      ),
    );
  }

  String? _nonNegative(String? value) {
    final number = double.tryParse(value ?? '');
    return number == null || number < 0 || !number.isFinite
        ? 'Masukkan angka nol atau lebih'
        : null;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tambah Barang Habis Pakai'),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('stock-name-input'),
                controller: _name,
                autofocus: true,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Nama barang'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null,
              ),
              DropdownButtonFormField<String>(
                key: const Key('stock-kind-input'),
                isExpanded: true,
                initialValue: _kindId,
                decoration: const InputDecoration(labelText: 'Jenis barang'),
                items: widget.kinds
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.id,
                        child: Text(e.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _kindId = v),
                validator: (v) => v == null ? 'Pilih jenis barang' : null,
              ),
              DropdownButtonFormField<String>(
                key: const Key('stock-category-input'),
                isExpanded: true,
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: widget.categories
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.id,
                        child: Text(e.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _categoryId = v),
                validator: (v) => v == null ? 'Pilih kategori' : null,
              ),
              TextFormField(
                key: const Key('stock-unit-input'),
                controller: _unit,
                maxLength: 32,
                decoration: const InputDecoration(
                  labelText: 'Satuan',
                  hintText: 'pcs, pak, botol',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Satuan wajib diisi' : null,
              ),
              DropdownButtonFormField<String>(
                key: const Key('stock-location-input'),
                isExpanded: true,
                initialValue: _locationId,
                decoration: const InputDecoration(
                  labelText: 'Lokasi penyimpanan',
                ),
                items: widget.locations
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.id,
                        child: Text(e.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _locationId = v),
                validator: (v) => v == null ? 'Pilih lokasi' : null,
              ),
              TextFormField(
                key: const Key('stock-initial-quantity-input'),
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Stok awal'),
                validator: _nonNegative,
              ),
              TextFormField(
                key: const Key('stock-minimum-input'),
                controller: _minimum,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Batas minimum'),
                validator: _nonNegative,
              ),
              const SizedBox(height: 8),
              const Text(
                'Stok awal dicatat untuk lokasi yang dipilih. Penambahan berikutnya dilakukan melalui mutasi stok.',
                style: TextStyle(fontSize: 12),
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
        onPressed:
            widget.kinds.isEmpty ||
                widget.categories.isEmpty ||
                widget.locations.isEmpty
            ? null
            : _submit,
        child: const Text('Simpan Barang'),
      ),
    ],
  );
}

class _EmptyStockItems extends StatelessWidget {
  const _EmptyStockItems();
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    alignment: Alignment.center,
    child: const Text(
      'Belum ada barang habis pakai. Tambahkan barang untuk mencatat stok awal.',
    ),
  );
}

String _formatQuantity(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);
