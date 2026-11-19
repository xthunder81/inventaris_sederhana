/// Model katalog lokasi, jenis, dan kategori untuk mengelompokkan barang.
///
/// CATATAN PEMELIHARAAN: samakan field model ini dengan koleksi
/// `locations`, `item_kinds`, dan `categories` pada `database/mongo/init.js`.
/// Ketiga katalog dibaca/disimpan melalui ApiClient. Fixture demo di bawah
/// hanya dipakai untuk tes HTTP/widget, bukan sebagai fallback produksi.
class MasterLocation {
  const MasterLocation({
    required this.id,
    required this.code,
    required this.name,
    required this.locationType,
    required this.isActive,
    this.parentId,
  });

  final String id;
  final String code;
  final String name;
  final String locationType;
  final String? parentId;
  final bool isActive;

  MasterLocation copyWith({bool? isActive}) {
    return MasterLocation(
      id: id,
      code: code,
      name: name,
      locationType: locationType,
      parentId: parentId,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Jenis barang, seperti aset tetap atau barang habis pakai.
class ItemKind {
  const ItemKind({
    required this.id,
    required this.code,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String code;
  final String name;
  final bool isActive;

  ItemKind copyWith({bool? isActive}) {
    return ItemKind(
      id: id,
      code: code,
      name: name,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Kategori untuk pengelompokan barang, dengan deskripsi opsional.
class ItemCategory {
  const ItemCategory({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.isActive,
  });

  final String id;
  final String code;
  final String name;
  final String description;
  final bool isActive;

  ItemCategory copyWith({bool? isActive}) {
    return ItemCategory(
      id: id,
      code: code,
      name: name,
      description: description,
      isActive: isActive ?? this.isActive,
    );
  }
}

// CATATAN TES: struktur contoh ini hanya fixture HTTP/widget; aplikasi nyata
// harus memuat lokasi per sekolah dari API dan tidak memakai daftar seed ini.
final demoLocations = <MasterLocation>[
  const MasterLocation(
    id: 'loc-001',
    code: 'SEK-001',
    name: 'SMP Negeri 1',
    locationType: 'sekolah',
    isActive: true,
  ),
  const MasterLocation(
    id: 'loc-002',
    code: 'GDG-001',
    name: 'Gedung Utama',
    locationType: 'gedung',
    parentId: 'loc-001',
    isActive: true,
  ),
  const MasterLocation(
    id: 'loc-003',
    code: 'RNG-001',
    name: 'Ruang Tata Usaha',
    locationType: 'ruang',
    parentId: 'loc-002',
    isActive: true,
  ),
  const MasterLocation(
    id: 'loc-004',
    code: 'RNG-002',
    name: 'Lab Komputer',
    locationType: 'ruang',
    parentId: 'loc-002',
    isActive: true,
  ),
  const MasterLocation(
    id: 'loc-005',
    code: 'GUD-001',
    name: 'Gudang Olahraga',
    locationType: 'gudang',
    parentId: 'loc-001',
    isActive: true,
  ),
  const MasterLocation(
    id: 'loc-006',
    code: 'RNG-003',
    name: 'Ruang 8A',
    locationType: 'ruang',
    parentId: 'loc-002',
    isActive: true,
  ),
  const MasterLocation(
    id: 'loc-007',
    code: 'RNG-004',
    name: 'Ruang 9B',
    locationType: 'ruang',
    parentId: 'loc-002',
    isActive: true,
  ),
];

// CATATAN TES: fixture item_kinds mengikuti bentuk koleksi init.js; produksi
// mengambil data aktual dari API dan tidak memakai katalog contoh ini.
final demoItemKinds = <ItemKind>[
  const ItemKind(
    id: 'kind-001',
    code: 'ASET-TETAP',
    name: 'Aset Tetap',
    isActive: true,
  ),
  const ItemKind(
    id: 'kind-002',
    code: 'HABIS-PAKAI',
    name: 'Barang Habis Pakai',
    isActive: true,
  ),
];

// CATATAN TES: fixture categories mengikuti bentuk koleksi init.js; deskripsi
// wajib dikirim meskipun nilainya boleh kosong.
final demoItemCategories = <ItemCategory>[
  const ItemCategory(
    id: 'cat-001',
    code: 'ELEKTRONIK',
    name: 'Elektronik',
    description: 'Perangkat listrik, komputer, dan perlengkapan digital.',
    isActive: true,
  ),
  const ItemCategory(
    id: 'cat-002',
    code: 'MEBEL',
    name: 'Mebel',
    description: 'Meja, kursi, lemari, dan perlengkapan ruang.',
    isActive: true,
  ),
  const ItemCategory(
    id: 'cat-003',
    code: 'ATK',
    name: 'Alat Tulis Kantor',
    description: 'Perlengkapan administrasi dan kegiatan belajar.',
    isActive: true,
  ),
  const ItemCategory(
    id: 'cat-004',
    code: 'OLAHRAGA',
    name: 'Olahraga',
    description: 'Peralatan olahraga dan pendidikan jasmani.',
    isActive: true,
  ),
];
