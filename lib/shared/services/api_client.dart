import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../features/inventory/models/inventory_item.dart';
import '../../features/inventory/models/stock_item.dart';
import '../../features/maintenance/models/maintenance_record.dart';
import '../../features/master_data/models/master_data.dart';
import '../../features/movements/models/stock_movement.dart';
import '../../features/users/models/user_account.dart';
import 'session_storage.dart';

/// Sesi API aktif; kredensial tidak pernah disimpan, hanya token berumur pendek.
class ApiSession {
  const ApiSession({
    required this.accessToken,
    required this.user,
    required this.expiresAt,
  });

  final String accessToken;
  final UserAccount user;
  final DateTime expiresAt;
}

/// Exception API dengan pesan aman untuk ditampilkan ke pengguna.
class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// CATATAN PEMELIHARAAN: seluruh komunikasi HTTP dan token bearer dipusatkan di
/// klien ini agar halaman tidak membentuk URL, JSON, atau auth header sendiri.
/// `API_BASE_URL` dapat diganti saat build untuk server lokal/LAN/produksi.
class ApiClient {
  ApiClient({
    http.Client? httpClient,
    Uri? baseUri,
    SessionStorage? sessionStorage,
  }) : _httpClient = httpClient ?? http.Client(),
       _sessionStorage = sessionStorage ?? createSessionStorage(),
       _baseUri =
           baseUri ??
           Uri.parse(
             const String.fromEnvironment(
               'API_BASE_URL',
               defaultValue: 'http://127.0.0.1:8081',
             ),
           );

  final http.Client _httpClient;
  final SessionStorage _sessionStorage;
  final Uri _baseUri;
  String? _accessToken;
  DateTime? _expiresAt;
  void Function()? onUnauthorized;

  bool get isAuthenticated => _accessToken != null;

  // CATATAN PEMELIHARAAN: token dan expiry ditulis setelah response tervalidasi;
  // backend tetap sumber masa berlaku, dan browser hanya memulihkan sesi yang
  // belum kedaluwarsa lalu meminta profil terbaru melalui endpoint /me.
  Future<ApiSession> login(String username, String password) async {
    final response = await _send(
      'POST',
      '/api/v1/auth/login',
      body: {'username': username, 'password': password},
      authenticated: false,
    );
    final data = _decodeObject(response.body);
    final token = data['access_token'];
    final userData = data['user'];
    final expires = DateTime.tryParse('${data['expires_at']}');
    if (token is! String || userData is! Map || expires == null) {
      throw const ApiException('Respons login dari server tidak valid.');
    }
    final user = _userFromJson(Map<String, dynamic>.from(userData));
    if (!expires.isAfter(DateTime.now().toUtc())) {
      throw const ApiException(
        'Server mengembalikan sesi yang sudah berakhir.',
      );
    }
    await _sessionStorage.write(
      PersistedApiSession(accessToken: token, expiresAt: expires),
    );
    _accessToken = token;
    _expiresAt = expires;
    return ApiSession(accessToken: token, expiresAt: expires, user: user);
  }

  // CATATAN PEMELIHARAAN: hanya token browser yang masih berlaku dipulihkan;
  // /me memeriksa status akun terkini. Sesi invalid/expired dihapus, sedangkan
  // kegagalan jaringan ditampilkan agar tidak diam-diam mengeluarkan pengguna.
  Future<UserAccount?> restoreSession() async {
    final storedSession = await _sessionStorage.read();
    if (storedSession == null) return null;
    if (!storedSession.expiresAt.isAfter(DateTime.now().toUtc())) {
      await logout();
      return null;
    }

    _accessToken = storedSession.accessToken;
    _expiresAt = storedSession.expiresAt;
    try {
      final response = await _send('GET', '/api/v1/auth/me');
      return _userFromJson(_decodeObject(response.body));
    } on ApiException {
      if (_accessToken == null) return null;
      rethrow;
    }
  }

  // CATATAN PEMELIHARAAN: UI memfilter/paginasi seluruh akun di perangkat;
  // ambil halaman API berurutan sampai total tercapai. Bila jumlah akun besar,
  // pindahkan pencarian/filter/paginasi ke server dan sesuaikan UsersPage.
  Future<List<UserAccount>> listUsers({int pageSize = 100}) async {
    final users = <UserAccount>[];
    var page = 1;
    var total = 0;
    do {
      final response = await _send(
        'GET',
        '/api/v1/users?page=$page&page_size=$pageSize',
      );
      final payload = _decodeObject(response.body);
      final data = payload['data'];
      final pageTotal = payload['total'];
      if (data is! List || pageTotal is! num || pageTotal < 0) {
        throw const ApiException(
          'Format daftar pengguna dari server tidak valid.',
        );
      }
      for (final item in data) {
        if (item is! Map) {
          throw const ApiException(
            'Daftar pengguna dari server berisi data yang tidak valid.',
          );
        }
        users.add(_userFromJson(Map<String, dynamic>.from(item)));
      }
      total = pageTotal.toInt();
      if (data.isEmpty && users.length < total) {
        throw const ApiException(
          'Daftar pengguna dari server belum lengkap; silakan muat ulang.',
        );
      }
      page++;
    } while (users.length < total);
    return users;
  }

  // CATATAN PEMELIHARAAN: API mengirim seluruh struktur termasuk arsip agar
  // halaman master dapat menampilkan status dan membangun dropdown induk.
  // Jika master lokasi membesar, pindahkan pencarian/paginasi ke server.
  Future<List<MasterLocation>> listLocations() async {
    final response = await _send('GET', '/api/v1/locations');
    final payload = _decodeObject(response.body);
    final data = payload['data'];
    final total = payload['total'];
    if (data is! List || total is! num || total < 0 || data.length != total) {
      throw const ApiException('Format daftar lokasi dari server tidak valid.');
    }
    return data.map((item) {
      if (item is! Map) {
        throw const ApiException(
          'Daftar lokasi dari server berisi data yang tidak valid.',
        );
      }
      return _locationFromJson(Map<String, dynamic>.from(item));
    }).toList();
  }

  // CATATAN PEMELIHARAAN: halaman memakai pagination lokal, jadi klien meminta
  // semua halaman aset secara berurutan dan menggabungkan event dari server.
  // Bila volume aset besar, pindahkan pencarian dan filter ke endpoint API.
  Future<InventorySnapshot> listAssets({int pageSize = 100}) async {
    final items = <InventoryItem>[];
    final events = <AssetConditionEvent>[];
    var page = 1;
    var total = 0;
    do {
      final response = await _send(
        'GET',
        '/api/v1/assets?page=$page&page_size=$pageSize',
      );
      final payload = _decodeObject(response.body);
      final data = payload['data'];
      final pageTotal = payload['total'];
      if (data is! List || pageTotal is! num || pageTotal < 0) {
        throw const ApiException('Format daftar aset dari server tidak valid.');
      }
      for (final entry in data) {
        if (entry is! Map) {
          throw const ApiException(
            'Daftar aset dari server berisi data yang tidak valid.',
          );
        }
        final parsed = _inventoryRecordFromJson(
          Map<String, dynamic>.from(entry),
        );
        items.add(parsed.item);
        events.addAll(parsed.events);
      }
      total = pageTotal.toInt();
      if (data.isEmpty && items.length < total) {
        throw const ApiException(
          'Daftar aset dari server belum lengkap; silakan muat ulang.',
        );
      }
      page++;
    } while (items.length < total);
    return InventorySnapshot(items: items, conditionEvents: events);
  }

  // CATATAN PEMELIHARAAN: saldo stok diambil bersama item agar layar inventaris
  // bisa menampilkan jumlah per lokasi; server menjadi sumber kebenaran stok.
  Future<List<StockItem>> listStockItems() async {
    final payload = _decodeObject(
      (await _send('GET', '/api/v1/stock-items')).body,
    );
    final data = payload['data'];
    if (data is! List) {
      throw const ApiException('Format daftar barang stok tidak valid.');
    }
    return data.map((entry) {
      if (entry is! Map) {
        throw const ApiException('Data barang stok tidak valid.');
      }
      return _stockItemFromJson(Map<String, dynamic>.from(entry));
    }).toList();
  }

  // CATATAN PEMELIHARAAN: hanya membuat item tracking_mode=stock beserta saldo
  // pembukanya. Perubahan sesudahnya harus dicatat lewat alur mutasi stok.
  Future<StockItem> createStockItem(StockItemInput input) async {
    final response = await _send(
      'POST',
      '/api/v1/stock-items',
      body: {
        'name': input.name,
        'kind_id': input.kindId,
        'category_id': input.categoryId,
        'unit': input.unit,
        'minimum_stock': input.minimumStock,
        'location_id': input.locationId,
        'initial_quantity': input.initialQuantity,
      },
    );
    final payload = _decodeObject(response.body);
    return _stockItemFromJson(payload);
  }

  // CATATAN PEMELIHARAAN: perubahan jumlah dikirim bersama lokasi dan alasan;
  // backend menulis adjustment posted agar koreksi bisa ditelusuri.
  Future<StockItem> updateStockItem(StockItemEditInput input) async {
    final response = await _send(
      'PATCH',
      '/api/v1/stock-items/${Uri.encodeComponent(input.itemId)}',
      body: {
        'name': input.name,
        'category_id': input.categoryId,
        'unit': input.unit,
        'minimum_stock': input.minimumStock,
        'location_id': input.locationId,
        'quantity': input.quantity,
        'notes': input.notes,
      },
    );
    return _stockItemFromJson(_decodeObject(response.body));
  }

  StockItem _stockItemFromJson(Map<String, dynamic> item) {
    final balances = item['balances'];
    if (balances is! List) {
      throw const ApiException('Saldo barang stok tidak valid.');
    }
    final itemId = item['item_id'],
        code = item['item_code'],
        name = item['name'];
    final kindId = item['kind_id'], categoryId = item['category_id'];
    final category = item['category'],
        unit = item['unit'],
        minimum = item['minimum_stock'];
    if (itemId is! String ||
        code is! String ||
        name is! String ||
        kindId is! String ||
        categoryId is! String ||
        category is! String ||
        unit is! String ||
        minimum is! num) {
      throw const ApiException('Data barang stok tidak lengkap.');
    }
    return StockItem(
      itemId: itemId,
      code: code,
      name: name,
      kindId: kindId,
      categoryId: categoryId,
      category: category,
      unit: unit,
      minimumStock: minimum.toDouble(),
      balances: balances.map((raw) {
        if (raw is! Map) {
          throw const ApiException('Saldo per lokasi tidak valid.');
        }
        final row = Map<String, dynamic>.from(raw);
        final locationId = row['location_id'],
            location = row['location'],
            quantity = row['quantity'];
        if (locationId is! String || location is! String || quantity is! num) {
          throw const ApiException('Saldo per lokasi tidak lengkap.');
        }
        return StockBalance(
          locationId: locationId,
          location: location,
          quantity: quantity.toDouble(),
        );
      }).toList(),
    );
  }

  // CATATAN PEMELIHARAAN: request hanya mengirim ID katalog dan label kondisi;
  // server memvalidasi referensi aktif, memilih jenis tidak habis pakai,
  // memakai item induk yang cocok, lalu membuat barcode unik untuk unit baru.
  Future<InventorySnapshot> createAsset({
    required String name,
    required String kindId,
    required String categoryId,
    required String locationId,
    required String condition,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/assets',
      body: {
        'name': name,
        'kind_id': kindId,
        'category_id': categoryId,
        'location_id': locationId,
        'condition': condition,
      },
    );
    final record = _inventoryRecordFromJson(_decodeObject(response.body));
    return InventorySnapshot(
      items: [record.item],
      conditionEvents: record.events,
    );
  }

  // CATATAN PEMELIHARAAN: pembaruan kondisi dikirim per ID unit aset dengan
  // catatan wajib; backend mengambil pelaku dari token dan menulis riwayat.
  Future<InventorySnapshot> changeAssetCondition({
    required String assetId,
    required String condition,
    required String notes,
  }) async {
    final response = await _send(
      'PATCH',
      '/api/v1/assets/${Uri.encodeComponent(assetId)}/condition',
      body: {'condition': condition, 'notes': notes},
    );
    final record = _inventoryRecordFromJson(_decodeObject(response.body));
    return InventorySnapshot(
      items: [record.item],
      conditionEvents: record.events,
    );
  }

  // CATATAN PEMELIHARAAN: PATCH mengirim nilai katalog, server mengubah unit
  // terpilih dan mencatat event; item induk bersama dipisah agar barcode lain
  // dengan nama/kategori lama tidak ikut berubah.
  Future<InventorySnapshot> updateAsset({required InventoryItem item}) async {
    final response = await _send(
      'PATCH',
      '/api/v1/assets/${Uri.encodeComponent(item.assetId!)}',
      body: {
        'name': item.name,
        'category_id': item.categoryId,
        'kind_id': item.kindId,
        'location_id': item.locationId,
        'condition': item.condition,
      },
    );
    final record = _inventoryRecordFromJson(_decodeObject(response.body));
    return InventorySnapshot(
      items: [record.item],
      conditionEvents: record.events,
    );
  }

  // CATATAN PEMELIHARAAN: arsip menghapus aset dari daftar aktif lewat status
  // server, sambil mempertahankan barcode, event, dan referensi transaksi.
  Future<void> archiveAsset({required String assetId}) async {
    await _send(
      'PATCH',
      '/api/v1/assets/${Uri.encodeComponent(assetId)}/archive',
    );
  }

  // CATATAN PEMELIHARAAN: daftar memuat halaman mutasi server dan detailnya;
  // pencarian/filter tetap lokal pada UI. Jika jumlah mutasi membesar, pindahkan
  // filter ke endpoint dan sesuaikan parameter tanpa mengubah mapping record.
  Future<List<StockMovement>> listMovements({int pageSize = 100}) async {
    final movements = <StockMovement>[];
    var page = 1;
    var total = 0;
    do {
      final response = await _send(
        'GET',
        '/api/v1/movements?page=$page&page_size=$pageSize',
      );
      final payload = _decodeObject(response.body);
      final data = payload['data'];
      final pageTotal = payload['total'];
      if (data is! List || pageTotal is! num || pageTotal < 0) {
        throw const ApiException(
          'Format daftar mutasi dari server tidak valid.',
        );
      }
      for (final entry in data) {
        if (entry is! Map) {
          throw const ApiException(
            'Daftar mutasi dari server berisi data yang tidak valid.',
          );
        }
        movements.add(_movementFromJson(Map<String, dynamic>.from(entry)));
      }
      total = pageTotal.toInt();
      if (data.isEmpty && movements.length < total) {
        throw const ApiException(
          'Daftar mutasi dari server belum lengkap; silakan muat ulang.',
        );
      }
      page++;
    } while (movements.length < total);
    return movements;
  }

  // CATATAN PEMELIHARAAN: klien mengirim satu baris draft dengan ID item/
  // lokasi master; server yang menetapkan nomor, pelaku, status, dan waktu.
  // Endpoint ini tidak memposting saldo dan mengembalikan record otoritatif.
  Future<StockMovement> createMovement(StockMovement movement) async {
    if (movement.lines.length != 1) {
      throw const ApiException('Draft mutasi harus berisi satu baris barang.');
    }
    final line = movement.lines.single;
    final response = await _send(
      'POST',
      '/api/v1/movements',
      body: {
        'movement_type': _movementTypeToApi(movement.type),
        'idempotency_key': movement.idempotencyKey,
        'line': {
          'item_id': line.itemId,
          'from_location_id': line.fromLocationId,
          'to_location_id': line.toLocationId,
          'quantity': line.quantity,
          'notes': line.notes,
        },
      },
    );
    return _movementFromJson(_decodeObject(response.body));
  }

  // CATATAN PEMELIHARAAN: server hanya membatalkan status draft; detail dan
  // saldo tidak dihapus/diubah. Respons menggantikan state lokal setelah sukses.
  Future<StockMovement> cancelMovement(String movementId) async {
    final response = await _send(
      'PATCH',
      '/api/v1/movements/${Uri.encodeComponent(movementId)}/cancel',
    );
    return _movementFromJson(_decodeObject(response.body));
  }

  // CATATAN PEMELIHARAAN: endpoint backend memvalidasi draft dan memposting
  // saldo/status/audit secara atomik. Gunakan record server sebagai state baru.
  Future<StockMovement> postMovement(String movementId) async {
    final response = await _send(
      'PATCH',
      '/api/v1/movements/${Uri.encodeComponent(movementId)}/post',
    );
    return _movementFromJson(_decodeObject(response.body));
  }

  // CATATAN PEMELIHARAAN: urutan halaman mempertahankan daftar lengkap untuk
  // filter/status dashboard; server menautkan laporan ke aset dan pelapor.
  Future<List<MaintenanceRecord>> listMaintenanceRecords() async {
    const pageSize = 100;
    var page = 1;
    var total = 0;
    final result = <MaintenanceRecord>[];
    do {
      final response = await _send(
        'GET',
        '/api/v1/maintenance-records?page=$page&page_size=$pageSize',
      );
      final payload = _decodeObject(response.body);
      final rawData = payload['data'];
      final rawTotal = payload['total'];
      if (rawData is! List || rawTotal is! num) {
        throw const ApiException('Daftar pemeliharaan dari server tidak valid.');
      }
      result.addAll(rawData.map((entry) {
        if (entry is! Map) {
          throw const ApiException('Laporan pemeliharaan dari server tidak valid.');
        }
        return _maintenanceRecordFromJson(Map<String, dynamic>.from(entry));
      }));
      total = rawTotal.toInt();
      if (rawData.isEmpty && result.length < total) {
        throw const ApiException('Halaman laporan pemeliharaan tidak lengkap.');
      }
      page++;
    } while (result.length < total);
    return result;
  }

  Future<MaintenanceRecord> createMaintenanceRecord(
    MaintenanceRecord record,
  ) async {
    final response = await _send(
      'POST',
      '/api/v1/maintenance-records',
      body: {
        'asset_id': record.assetId,
        'description': record.description,
      },
    );
    return _maintenanceRecordFromJson(_decodeObject(response.body));
  }

  Future<MaintenanceRecord> updateMaintenanceRecord(
    MaintenanceRecord record,
  ) async {
    final response = await _send(
      'PATCH',
      '/api/v1/maintenance-records/${Uri.encodeComponent(record.id)}',
      body: {'status': _maintenanceStatusToApi(record.status), 'cost': record.cost},
    );
    return _maintenanceRecordFromJson(_decodeObject(response.body));
  }

  MaintenanceRecord _maintenanceRecordFromJson(Map<String, dynamic> data) {
    final id = data['id'];
    final assetId = data['asset_id'];
    final assetCode = data['asset_code'];
    final assetName = data['asset_name'];
    final reportedBy = data['reported_by'];
    final status = data['status'];
    final description = data['description'];
    final cost = data['cost'];
    final reportedAt = DateTime.tryParse('${data['reported_at']}');
    final closedAt = switch (data['closed_at']) {
      null => null,
      String value when DateTime.tryParse(value) != null => DateTime.parse(value),
      _ => throw const ApiException('Tanggal penutupan laporan tidak valid.'),
    };
    if (id is! String || assetId is! String || assetCode is! String ||
        assetName is! String || reportedBy is! String || status is! String ||
        description is! String || cost is! num || reportedAt == null ||
        !cost.toDouble().isFinite || cost < 0) {
      throw const ApiException('Data laporan pemeliharaan tidak lengkap.');
    }
    return MaintenanceRecord(
      id: id,
      assetId: assetId,
      assetCode: assetCode,
      assetName: assetName,
      reportedBy: reportedBy,
      status: _maintenanceStatusFromApi(status),
      description: description,
      cost: cost.toDouble(),
      reportedAt: reportedAt,
      closedAt: closedAt,
    );
  }

  MaintenanceStatus _maintenanceStatusFromApi(String value) => switch (value) {
    'reported' => MaintenanceStatus.reported,
    'in_progress' => MaintenanceStatus.inProgress,
    'completed' => MaintenanceStatus.completed,
    'cancelled' => MaintenanceStatus.cancelled,
    _ => throw const ApiException('Status pemeliharaan tidak dikenal.'),
  };

  String _maintenanceStatusToApi(MaintenanceStatus value) => switch (value) {
    MaintenanceStatus.reported => 'reported',
    MaintenanceStatus.inProgress => 'in_progress',
    MaintenanceStatus.completed => 'completed',
    MaintenanceStatus.cancelled => 'cancelled',
  };

  // CATATAN PEMELIHARAAN: ID sementara dari dialog hanya untuk pembeda create
  // dan edit di UI; server membuat UUID dan mengembalikan record otoritatif.
  // Backend menormalisasi kode serta memeriksa induk dan kode unik.
  Future<MasterLocation> createLocation(MasterLocation location) async {
    final response = await _send(
      'POST',
      '/api/v1/locations',
      body: _locationToJson(location),
    );
    return _locationFromJson(_decodeObject(response.body));
  }

  // CATATAN PEMELIHARAAN: edit/status aktif mengirim seluruh field mutable
  // sehingga is_active:false dan parent_id:null tidak ambigu di server.
  // Server menolak siklus, induk nonaktif, serta arsip induk dengan anak aktif.
  Future<MasterLocation> updateLocation(MasterLocation location) async {
    final response = await _send(
      'PATCH',
      '/api/v1/locations/${Uri.encodeComponent(location.id)}',
      body: _locationToJson(location),
    );
    return _locationFromJson(_decodeObject(response.body));
  }

  // CATATAN PEMELIHARAAN: jenis barang dan kategori diambil terpisah sesuai
  // koleksi Mongo masing-masing; daftar memuat record aktif maupun arsip agar
  // status dapat ditampilkan dan record lama dapat diaktifkan kembali.
  Future<List<ItemKind>> listItemKinds() async {
    final response = await _send('GET', '/api/v1/item-kinds');
    final payload = _decodeObject(response.body);
    final data = payload['data'];
    final total = payload['total'];
    if (data is! List || total is! num || total < 0 || data.length != total) {
      throw const ApiException(
        'Format daftar jenis barang dari server tidak valid.',
      );
    }
    return data.map((item) {
      if (item is! Map) {
        throw const ApiException(
          'Daftar jenis barang dari server berisi data yang tidak valid.',
        );
      }
      return _itemKindFromJson(Map<String, dynamic>.from(item));
    }).toList();
  }

  Future<List<ItemCategory>> listCategories() async {
    final response = await _send('GET', '/api/v1/categories');
    final payload = _decodeObject(response.body);
    final data = payload['data'];
    final total = payload['total'];
    if (data is! List || total is! num || total < 0 || data.length != total) {
      throw const ApiException(
        'Format daftar kategori dari server tidak valid.',
      );
    }
    return data.map((item) {
      if (item is! Map) {
        throw const ApiException(
          'Daftar kategori dari server berisi data yang tidak valid.',
        );
      }
      return _categoryFromJson(Map<String, dynamic>.from(item));
    }).toList();
  }

  // CATATAN PEMELIHARAAN: dialog memakai ID sementara hanya untuk membedakan
  // create/edit; server membuat UUID dan menetapkan kode/status resmi.
  Future<ItemKind> createItemKind(ItemKind itemKind) async {
    final response = await _send(
      'POST',
      '/api/v1/item-kinds',
      body: {
        'code': itemKind.code,
        'name': itemKind.name,
        'is_active': itemKind.isActive,
      },
    );
    return _itemKindFromJson(_decodeObject(response.body));
  }

  Future<ItemKind> updateItemKind(ItemKind itemKind) async {
    final response = await _send(
      'PATCH',
      '/api/v1/item-kinds/${Uri.encodeComponent(itemKind.id)}',
      body: {
        'code': itemKind.code,
        'name': itemKind.name,
        'is_active': itemKind.isActive,
      },
    );
    return _itemKindFromJson(_decodeObject(response.body));
  }

  Future<ItemCategory> createCategory(ItemCategory category) async {
    final response = await _send(
      'POST',
      '/api/v1/categories',
      body: {
        'code': category.code,
        'name': category.name,
        'description': category.description,
        'is_active': category.isActive,
      },
    );
    return _categoryFromJson(_decodeObject(response.body));
  }

  Future<ItemCategory> updateCategory(ItemCategory category) async {
    final response = await _send(
      'PATCH',
      '/api/v1/categories/${Uri.encodeComponent(category.id)}',
      body: {
        'code': category.code,
        'name': category.name,
        'description': category.description,
        'is_active': category.isActive,
      },
    );
    return _categoryFromJson(_decodeObject(response.body));
  }

  // CATATAN PEMELIHARAAN: password hanya ada di request create dan tidak
  // disimpan pada UserAccount; server bertanggung jawab membuat hash Argon2id.
  Future<UserAccount> createUser({
    required UserAccount user,
    required String password,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/users',
      body: {
        'username': user.username,
        'full_name': user.name,
        'role': _roleToApi(user.role),
        'password': password,
      },
    );
    return _userFromJson(_decodeObject(response.body));
  }

  // CATATAN PEMELIHARAAN: field yang dikirim harus sesuai DTO PATCH server;
  // backend mengembalikan record otoritatif yang menggantikan state UI lokal.
  Future<UserAccount> updateUser(UserAccount user) async {
    final response = await _send(
      'PATCH',
      '/api/v1/users/${Uri.encodeComponent(user.id)}',
      body: {
        'username': user.username,
        'full_name': user.name,
        'role': _roleToApi(user.role),
        'is_active': user.isActive,
      },
    );
    return _userFromJson(_decodeObject(response.body));
  }

  // CATATAN PEMELIHARAAN: endpoint hanya mengubah password sesi yang sedang
  // aktif setelah server memverifikasi currentPassword; jangan log body request.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _send(
      'POST',
      '/api/v1/auth/change-password',
      body: {'current_password': currentPassword, 'new_password': newPassword},
    );
  }

  // CATATAN PEMELIHARAAN: logout menghapus token lokal; backend belum punya
  // revoke/blacklist, sehingga salinan token tetap berlaku sampai expiry.
  Future<void> logout() async {
    _accessToken = null;
    _expiresAt = null;
    await _sessionStorage.clear();
  }

  // CATATAN PEMELIHARAAN: pemilik ApiClient menutup transport saat lifecycle
  // berakhir; jangan menutupnya setelah tiap request karena client dipakai ulang.
  void close() {
    _httpClient.close();
  }

  // CATATAN PEMELIHARAAN: semua request melewati helper ini untuk base URL,
  // bearer, serialisasi, pemetaan error, dan invalidasi sesi pada HTTP 401.
  // Kontrak body/route harus diselaraskan dengan backend dan tes HTTP fixture.
  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool authenticated = true,
  }) async {
    final uri = _baseUri.resolve(path);
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (authenticated) {
      final token = _accessToken;
      if (token == null) {
        throw const ApiException('Sesi berakhir. Silakan masuk kembali.');
      }
      final expiresAt = _expiresAt;
      if (expiresAt != null && !expiresAt.isAfter(DateTime.now().toUtc())) {
        await logout();
        onUnauthorized?.call();
        throw const ApiException('Sesi berakhir. Silakan masuk kembali.');
      }
      headers['Authorization'] = 'Bearer $token';
    }

    final encodedBody = body == null ? null : jsonEncode(body);
    late final http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _httpClient
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 20));
        case 'POST':
          response = await _httpClient
              .post(uri, headers: headers, body: encodedBody)
              .timeout(const Duration(seconds: 20));
        case 'PATCH':
          response = await _httpClient
              .patch(uri, headers: headers, body: encodedBody)
              .timeout(const Duration(seconds: 20));
        default:
          throw StateError('Metode HTTP tidak didukung: $method');
      }
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException('Tidak dapat terhubung ke server API: $error');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decodedMessage = _decodeError(response.body);
      final message =
          decodedMessage ??
          (response.statusCode == 404 && path.startsWith('/api/v1/stock-items')
              ? 'Endpoint barang stok belum tersedia di server. Restart API dengan go run ./cmd/server, lalu coba lagi.'
              : 'Permintaan gagal (HTTP ${response.statusCode}).');
      if (response.statusCode == 401) {
        await logout();
        onUnauthorized?.call();
      }
      throw ApiException(message);
    }
    return response;
  }

  // CATATAN PEMELIHARAAN: hanya objek JSON diterima; endpoint yang mengubah
  // response menjadi array atau envelope baru harus memperbarui pemetaan ini.
  Map<String, dynamic> _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      throw const ApiException('Server mengirim data yang tidak dapat dibaca.');
    }
    throw const ApiException('Format data dari server tidak valid.');
  }

  // CATATAN PEMELIHARAAN: detail error dibaca hanya dari key `error`; bila
  // server mengubah format, sesuaikan di sini tanpa menampilkan payload mentah.
  String? _decodeError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  // CATATAN PEMELIHARAAN: mapping menolak field wajib yang hilang dan menjaga
  // password hash tidak masuk model UI; field server baru perlu dipetakan
  // eksplisit sebelum dipakai oleh halaman.
  UserAccount _userFromJson(Map<String, dynamic> data) {
    final id = data['id'];
    final name = data['full_name'];
    final username = data['username'];
    final role = data['role'];
    final isActive = data['is_active'];
    if (id is! String ||
        name is! String ||
        username is! String ||
        role is! String ||
        isActive is! bool) {
      throw const ApiException('Data akun dari server tidak lengkap.');
    }
    final rawLastLogin = data['last_login_at'];
    final lastLoginAt = switch (rawLastLogin) {
      null => null,
      String value when DateTime.tryParse(value) != null => DateTime.parse(
        value,
      ),
      _ => throw const ApiException(
        'Waktu login terakhir dari server tidak valid.',
      ),
    };
    return UserAccount(
      id: id,
      name: name,
      username: username,
      role: _roleFromApi(role),
      isActive: isActive,
      lastLoginAt: lastLoginAt,
    );
  }

  MasterLocation _locationFromJson(Map<String, dynamic> data) {
    final id = data['id'];
    final code = data['code'];
    final name = data['name'];
    final locationType = data['location_type'];
    final parentId = data['parent_id'];
    final isActive = data['is_active'];
    if (id is! String ||
        code is! String ||
        name is! String ||
        locationType is! String ||
        (parentId != null && parentId is! String) ||
        isActive is! bool) {
      throw const ApiException('Data lokasi dari server tidak lengkap.');
    }
    final parsedParentId = parentId is String ? parentId : null;
    return MasterLocation(
      id: id,
      code: code,
      name: name,
      locationType: locationType,
      parentId: parsedParentId,
      isActive: isActive,
    );
  }

  ItemKind _itemKindFromJson(Map<String, dynamic> data) {
    final id = data['id'];
    final code = data['code'];
    final name = data['name'];
    final isActive = data['is_active'];
    if (id is! String ||
        code is! String ||
        name is! String ||
        isActive is! bool) {
      throw const ApiException('Data jenis barang dari server tidak lengkap.');
    }
    return ItemKind(id: id, code: code, name: name, isActive: isActive);
  }

  ItemCategory _categoryFromJson(Map<String, dynamic> data) {
    final id = data['id'];
    final code = data['code'];
    final name = data['name'];
    final description = data['description'];
    final isActive = data['is_active'];
    if (id is! String ||
        code is! String ||
        name is! String ||
        description is! String ||
        isActive is! bool) {
      throw const ApiException('Data kategori dari server tidak lengkap.');
    }

    return ItemCategory(
      id: id,
      code: code,
      name: name,
      description: description,
      isActive: isActive,
    );
  }

  StockMovement _movementFromJson(Map<String, dynamic> data) {
    final id = data['id'];
    final movementNumber = data['movement_number'];
    final rawType = data['movement_type'];
    final rawStatus = data['status'];
    final idempotencyKey = data['idempotency_key'];
    final performedBy = data['performed_by'];
    final createdAt = DateTime.tryParse('${data['created_at']}');
    final rawLines = data['lines'];
    if (id is! String ||
        movementNumber is! String ||
        rawType is! String ||
        rawStatus is! String ||
        idempotencyKey is! String ||
        performedBy is! String ||
        createdAt == null ||
        rawLines is! List ||
        rawLines.isEmpty) {
      throw const ApiException('Data mutasi dari server tidak lengkap.');
    }
    final postedAt = switch (data['posted_at']) {
      null => null,
      String value when DateTime.tryParse(value) != null => DateTime.parse(
        value,
      ),
      _ => throw const ApiException(
        'Waktu posting mutasi dari server tidak valid.',
      ),
    };
    final lines = rawLines.map((entry) {
      if (entry is! Map) {
        throw const ApiException('Baris mutasi dari server tidak valid.');
      }
      final line = Map<String, dynamic>.from(entry);
      final itemId = line['item_id'];
      final itemName = line['item_name'];
      final quantity = line['quantity'];
      final notes = line['notes'];
      final fromLocationId = line['from_location_id'];
      final fromLocationName = line['from_location_name'];
      final toLocationId = line['to_location_id'];
      final toLocationName = line['to_location_name'];
      if (itemId is! String ||
          itemName is! String ||
          quantity is! num ||
          !quantity.toDouble().isFinite ||
          quantity <= 0 ||
          notes is! String ||
          (fromLocationId != null && fromLocationId is! String) ||
          (fromLocationName != null && fromLocationName is! String) ||
          (toLocationId != null && toLocationId is! String) ||
          (toLocationName != null && toLocationName is! String)) {
        throw const ApiException('Baris mutasi dari server tidak lengkap.');
      }
      return StockMovementLine(
        itemId: itemId,
        itemName: itemName,
        quantity: quantity.toDouble(),
        notes: notes,
        fromLocationId: fromLocationId,
        fromLocationName: fromLocationName,
        toLocationId: toLocationId,
        toLocationName: toLocationName,
      );
    }).toList();
    return StockMovement(
      id: id,
      movementNumber: movementNumber,
      type: _movementTypeFromApi(rawType),
      status: _movementStatusFromApi(rawStatus),
      idempotencyKey: idempotencyKey,
      performedBy: performedBy,
      createdAt: createdAt,
      postedAt: postedAt,
      lines: lines,
    );
  }

  MovementType _movementTypeFromApi(String value) => switch (value) {
    'receipt' => MovementType.receipt,
    'issue' => MovementType.issue,
    'transfer' => MovementType.transfer,
    'adjustment' => MovementType.adjustment,
    _ => throw const ApiException('Jenis mutasi dari server tidak dikenal.'),
  };

  MovementStatus _movementStatusFromApi(String value) => switch (value) {
    'draft' => MovementStatus.draft,
    'posted' => MovementStatus.posted,
    'cancelled' => MovementStatus.cancelled,
    _ => throw const ApiException('Status mutasi dari server tidak dikenal.'),
  };

  String _movementTypeToApi(MovementType value) => switch (value) {
    MovementType.receipt => 'receipt',
    MovementType.issue => 'issue',
    MovementType.transfer => 'transfer',
    MovementType.adjustment => 'adjustment',
  };

  // CATATAN PEMELIHARAAN: record API memuat tampilan aset dan riwayat audit;
  // field wajib divalidasi sebelum model dipakai agar respons parsial tidak
  // terlihat seperti aset yang berhasil dimuat.
  ({InventoryItem item, List<AssetConditionEvent> events})
  _inventoryRecordFromJson(Map<String, dynamic> data) {
    final assetId = data['asset_id'];
    final itemId = data['item_id'];
    final kindId = data['kind_id'];
    final code = data['asset_code'];
    final name = data['name'];
    final categoryId = data['category_id'];
    final category = data['category'];
    final locationId = data['location_id'];
    final location = data['location'];
    final condition = data['condition'];
    final rawEvents = data['events'];
    if (assetId is! String ||
        itemId is! String ||
        kindId is! String ||
        code is! String ||
        name is! String ||
        categoryId is! String ||
        category is! String ||
        locationId is! String ||
        location is! String ||
        condition is! String ||
        rawEvents is! List) {
      throw const ApiException('Data aset dari server tidak lengkap.');
    }
    final rawCreatedAt = data['created_at'];
    if (rawCreatedAt is! String || DateTime.tryParse(rawCreatedAt) == null) {
      throw const ApiException('Waktu pembuatan aset dari server tidak valid.');
    }
    final events = rawEvents.map((entry) {
      if (entry is! Map) {
        throw const ApiException('Riwayat aset dari server tidak valid.');
      }
      final event = Map<String, dynamic>.from(entry);
      final eventType = event['event_type'];
      final previousCondition = event['previous_condition'];
      final newCondition = event['new_condition'];
      final performedBy = event['performed_by'];
      final notes = event['notes'];
      final rawOccurredAt = event['occurred_at'];
      if (eventType is! String ||
          previousCondition is! String ||
          newCondition is! String ||
          performedBy is! String ||
          notes is! String ||
          rawOccurredAt is! String ||
          DateTime.tryParse(rawOccurredAt) == null) {
        throw const ApiException('Riwayat aset dari server tidak lengkap.');
      }
      return AssetConditionEvent(
        eventType: eventType,
        assetCode: code,
        previousCondition: previousCondition,
        newCondition: newCondition,
        performedBy: performedBy,
        notes: notes,
        occurredAt: DateTime.parse(rawOccurredAt),
      );
    }).toList();
    return (
      item: InventoryItem.fromServer(
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
      ),
      events: events,
    );
  }

  Map<String, Object?> _locationToJson(MasterLocation location) => {
    'code': location.code,
    'name': location.name,
    'parent_id': location.parentId,
    'location_type': location.locationType,
    'is_active': location.isActive,
  };

  // CATATAN PEMELIHARAAN: Flutter menampilkan label peran berkapitalisasi,
  // sedangkan API menerima enum huruf kecil; selaraskan kedua mapping saat
  // menambah peran baru.
  String _roleToApi(String role) => switch (role.toLowerCase()) {
    'admin' => 'admin',
    'petugas' => 'petugas',
    'pimpinan' => 'pimpinan',
    _ => throw ApiException('Peran "$role" tidak dikenal.'),
  };

  // CATATAN PEMELIHARAAN: role yang tidak dikenal ditolak, bukan diganti
  // menjadi peran default yang dapat menyesatkan hak akses UI.
  String _roleFromApi(String role) => switch (role) {
    'admin' => 'Admin',
    'petugas' => 'Petugas',
    'pimpinan' => 'Pimpinan',
    _ => throw ApiException(
      'Server mengirim peran "$role" yang tidak dikenal.',
    ),
  };
}
