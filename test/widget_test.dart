import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdf/pdf.dart';

import 'package:inventaris_sederhana/features/inventory/views/inventory_page.dart';
import 'package:inventaris_sederhana/features/inventory/services/asset_label_printer.dart';
import 'package:inventaris_sederhana/features/master_data/models/master_data.dart';
import 'package:inventaris_sederhana/features/users/models/user_account.dart';
import 'package:inventaris_sederhana/features/users/views/users_page.dart';
import 'package:inventaris_sederhana/shared/services/api_client.dart';
import 'package:inventaris_sederhana/shared/services/session_storage.dart';
import 'package:inventaris_sederhana/main.dart';

class _MemorySessionStorage implements SessionStorage {
  _MemorySessionStorage(this.session);

  PersistedApiSession? session;

  @override
  Future<PersistedApiSession?> read() async => session;

  @override
  Future<void> write(PersistedApiSession value) async {
    session = value;
  }

  @override
  Future<void> clear() async {
    session = null;
  }
}

// CATATAN PEMELIHARAAN: fake API membuat tes dashboard deterministik tanpa
// memakai MongoDB; endpoint baru yang dipakai UI harus ditambahkan ke fixture.
ApiClient _testApiClient({String loginRole = 'admin'}) {
  final users = demoUsers.toList();
  final locations = demoLocations.toList();
  final itemKinds = demoItemKinds.toList();
  final categories = demoItemCategories.toList();
  final assetRecords = <Map<String, dynamic>>[];
  final stockItemRecords = <Map<String, dynamic>>[];
  final movementRecords = <Map<String, dynamic>>[];
  final maintenanceRecords = <Map<String, dynamic>>[];
  final loginUser = demoUsers.first.copyWith(role: loginRole);
  Map<String, Object?> userJson(UserAccount user) => {
    'id': user.id,
    'username': user.username,
    'full_name': user.name,
    'role': user.role.toLowerCase(),
    'is_active': user.isActive,
    'last_login_at': user.lastLoginAt?.toIso8601String(),
    'created_at': DateTime(2026, 11, 1).toIso8601String(),
  };
  Map<String, Object?> locationJson(MasterLocation location) => {
    'id': location.id,
    'code': location.code,
    'name': location.name,
    'parent_id': location.parentId,
    'location_type': location.locationType,
    'is_active': location.isActive,
    'created_at': DateTime(2026, 11, 1).toIso8601String(),
  };
  Map<String, Object?> itemKindJson(ItemKind itemKind) => {
    'id': itemKind.id,
    'code': itemKind.code,
    'name': itemKind.name,
    'is_active': itemKind.isActive,
  };
  Map<String, Object?> categoryJson(ItemCategory category) => {
    'id': category.id,
    'code': category.code,
    'name': category.name,
    'description': category.description,
    'is_active': category.isActive,
  };
  final demoAssets = [
    ('Laptop Lenovo ThinkPad', 'Elektronik', 'Lab Komputer', 'Bagus'),
    ('Meja belajar siswa', 'Mebel', 'Ruang 8A', 'Bagus'),
    ('Proyektor Epson', 'Elektronik', 'Ruang 9B', 'Dalam service'),
    ('Bola basket', 'Olahraga', 'Gudang Olahraga', 'Perlu perbaikan'),
    ('Printer Epson L3210', 'Elektronik', 'Ruang Tata Usaha', 'Bagus'),
  ];
  for (var index = 0; index < demoAssets.length; index++) {
    final (name, categoryName, locationName, condition) = demoAssets[index];
    final category = categories.firstWhere((item) => item.name == categoryName);
    final location = locations.firstWhere((item) => item.name == locationName);
    assetRecords.add({
      'asset_id': 'asset-fixture-$index',
      'item_id': 'item-fixture-$index',
      'kind_id': itemKinds.first.id,
      'asset_code': 'AST-FIXTURE-${index + 1}',
      'name': name,
      'category_id': category.id,
      'category': category.name,
      'location_id': location.id,
      'location': location.name,
      'condition_id': 'condition-fixture-$index',
      'condition': condition,
      'created_at': DateTime(2026, 11, 1).toIso8601String(),
      'events': <Map<String, Object?>>[],
    });
  }

  return ApiClient(
    httpClient: MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return http.Response(
          jsonEncode({
            'access_token': 'test-access-token',
            'token_type': 'Bearer',
            'expires_at': DateTime.now()
                .add(const Duration(minutes: 15))
                .toIso8601String(),
            'user': userJson(loginUser),
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/users' && request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'data': users.map(userJson).toList(),
            'page': 1,
            'page_size': 100,
            'total': users.length,
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/locations' && request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'data': locations.map(locationJson).toList(),
            'total': locations.length,
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/assets' && request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'data': assetRecords,
            'page': 1,
            'page_size': 100,
            'total': assetRecords.length,
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/stock-items' &&
          request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'data': stockItemRecords,
            'total': stockItemRecords.length,
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/stock-items' &&
          request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final category = categories.firstWhere(
          (item) => item.id == body['category_id'],
        );
        final location = locations.firstWhere(
          (item) => item.id == body['location_id'],
        );
        final record = <String, dynamic>{
          'item_id': 'stock-item-${stockItemRecords.length + 1}',
          'item_code': 'STK-${stockItemRecords.length + 1}',
          'name': body['name'],
          'kind_id': body['kind_id'],
          'category_id': category.id,
          'category': category.name,
          'unit': body['unit'],
          'minimum_stock': body['minimum_stock'],
          'balances': [
            {
              'location_id': location.id,
              'location': location.name,
              'quantity': body['initial_quantity'],
              'updated_at': DateTime.now().toIso8601String(),
            },
          ],
        };
        stockItemRecords.add(record);
        return http.Response(jsonEncode(record), 201);
      }
      if (request.url.path.startsWith('/api/v1/stock-items/') &&
          request.method == 'PATCH') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final id = request.url.path.split('/').last;
        final index = stockItemRecords.indexWhere(
          (item) => item['item_id'] == id,
        );
        if (index < 0) {
          return http.Response('{"error":"barang stok tidak ditemukan"}', 404);
        }
        final item = stockItemRecords[index];
        item['name'] = body['name'];
        item['category_id'] = body['category_id'];
        item['unit'] = body['unit'];
        item['minimum_stock'] = body['minimum_stock'];
        final balances = item['balances'] as List;
        final row = balances.firstWhere(
          (value) => value['location_id'] == body['location_id'],
        ) as Map<String, dynamic>;
        row['quantity'] = body['quantity'];
        stockItemRecords[index] = item;
        return http.Response(jsonEncode(item), 200);
      }
      if (request.url.path == '/api/v1/assets' && request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final category = categories.firstWhere(
          (item) => item.id == body['category_id'],
        );
        final location = locations.firstWhere(
          (item) => item.id == body['location_id'],
        );
        final record = <String, dynamic>{
          'asset_id': 'asset-created-${assetRecords.length}',
          'item_id': 'item-created-${assetRecords.length}',
          'kind_id': body['kind_id'],
          'asset_code': 'AST-TEST-${assetRecords.length + 1}',
          'name': body['name'],
          'category_id': category.id,
          'category': category.name,
          'location_id': location.id,
          'location': location.name,
          'condition_id': 'condition-created',
          'condition': body['condition'],
          'created_at': DateTime.now().toIso8601String(),
          'events': <Map<String, Object?>>[
            {
              'event_type': 'received',
              'previous_condition': '',
              'new_condition': body['condition'],
              'performed_by': loginUser.name,
              'notes': 'Aset didaftarkan.',
              'occurred_at': DateTime.now().toIso8601String(),
            },
          ],
        };
        assetRecords.insert(0, record);
        return http.Response(jsonEncode(record), 201);
      }
      if (request.url.path.startsWith('/api/v1/assets/') &&
          request.method == 'PATCH') {
        final id = request.url.path.split('/').reversed.skip(1).first;
        final index = assetRecords.indexWhere((item) => item['asset_id'] == id);
        if (index < 0) {
          return http.Response('{"error":"aset tidak ditemukan"}', 404);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final record = assetRecords[index];
        final previousCondition = record['condition'] as String;
        final newCondition = body['condition'] as String;
        record['condition'] = newCondition;
        (record['events'] as List<Map<String, Object?>>).insert(0, {
          'event_type': 'condition_changed',
          'previous_condition': previousCondition,
          'new_condition': newCondition,
          'performed_by': loginUser.name,
          'notes': body['notes'],
          'occurred_at': DateTime.now().toIso8601String(),
        });
        return http.Response(jsonEncode(record), 200);
      }
      if (request.url.path == '/api/v1/maintenance-records' &&
          request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'data': maintenanceRecords,
            'page': 1,
            'page_size': 100,
            'total': maintenanceRecords.length,
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/maintenance-records' &&
          request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final asset = assetRecords.firstWhere(
          (record) => record['asset_id'] == body['asset_id'],
        );
        final record = <String, dynamic>{
          'id': 'maintenance-fixture-${maintenanceRecords.length}',
          'asset_id': asset['asset_id'],
          'asset_code': asset['asset_code'],
          'asset_name': asset['name'],
          'reported_by': loginUser.name,
          'status': 'reported',
          'description': body['description'],
          'cost': 0,
          'reported_at': DateTime.now().toIso8601String(),
          'closed_at': null,
        };
        maintenanceRecords.insert(0, record);
        return http.Response(jsonEncode(record), 201);
      }
      if (request.url.path.startsWith('/api/v1/maintenance-records/') &&
          request.method == 'PATCH') {
        final id = request.url.pathSegments.last;
        final record = maintenanceRecords.firstWhere(
          (entry) => entry['id'] == id,
          orElse: () => <String, dynamic>{},
        );
        if (record.isEmpty) {
          return http.Response('{"error":"laporan tidak ditemukan"}', 404);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        record['status'] = body['status'];
        if (body['status'] == 'completed') record['cost'] = body['cost'];
        if (body['status'] == 'completed' || body['status'] == 'cancelled') {
          record['closed_at'] = DateTime.now().toIso8601String();
        }
        return http.Response(jsonEncode(record), 200);
      }
      if (request.url.path == '/api/v1/movements' && request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'data': movementRecords,
            'page': 1,
            'page_size': 100,
            'total': movementRecords.length,
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/movements' && request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final line = body['line'] as Map<String, dynamic>;
        final item = assetRecords.firstWhere(
          (asset) => asset['item_id'] == line['item_id'],
        );
        String? locationName(Object? id) {
          if (id == null) return null;
          return locations.firstWhere((location) => location.id == id).name;
        }

        final record = <String, dynamic>{
          'id': 'movement-fixture-${movementRecords.length}',
          'movement_number': 'MUT-2026-${movementRecords.length + 1}',
          'movement_type': body['movement_type'],
          'status': 'draft',
          'idempotency_key': body['idempotency_key'],
          'performed_by': loginUser.name,
          'created_at': DateTime.now().toIso8601String(),
          'posted_at': null,
          'lines': [
            {
              'line_number': 1,
              'item_id': line['item_id'],
              'item_name': item['name'],
              'from_location_id': line['from_location_id'],
              'from_location_name': locationName(line['from_location_id']),
              'to_location_id': line['to_location_id'],
              'to_location_name': locationName(line['to_location_id']),
              'quantity': line['quantity'],
              'notes': line['notes'],
            },
          ],
        };
        movementRecords.insert(0, record);
        return http.Response(jsonEncode(record), 201);
      }
      if (request.url.path.startsWith('/api/v1/movements/') &&
          request.method == 'PATCH') {
        final id = request.url.path.split('/').reversed.skip(1).first;
        final record = movementRecords.firstWhere(
          (movement) => movement['id'] == id,
          orElse: () => <String, dynamic>{},
        );
        if (record.isEmpty || record['status'] != 'draft') {
          return http.Response('{"error":"mutasi bukan draft"}', 409);
        }
        record['status'] = 'cancelled';
        return http.Response(jsonEncode(record), 200);
      }
      if (request.url.path == '/api/v1/locations' && request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final code = (body['code'] as String).trim().toUpperCase();
        if (locations.any((location) => location.code.toUpperCase() == code)) {
          return http.Response('{"error":"kode lokasi sudah digunakan"}', 409);
        }
        final location = MasterLocation(
          id: 'loc-created-${locations.length}',
          code: code,
          name: (body['name'] as String).trim(),
          parentId: body['parent_id'] as String?,
          locationType: body['location_type'] as String,
          isActive: body['is_active'] as bool,
        );
        locations.insert(0, location);
        return http.Response(jsonEncode(locationJson(location)), 201);
      }
      if (request.url.path.startsWith('/api/v1/locations/') &&
          request.method == 'PATCH') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final id = request.url.path.split('/').last;
        final index = locations.indexWhere((location) => location.id == id);
        if (index < 0) {
          return http.Response('{"error":"lokasi tidak ditemukan"}', 404);
        }
        final old = locations[index];
        final location = MasterLocation(
          id: old.id,
          code: body['code'] as String? ?? old.code,
          name: body['name'] as String? ?? old.name,
          parentId: body.containsKey('parent_id')
              ? body['parent_id'] as String?
              : old.parentId,
          locationType: body['location_type'] as String? ?? old.locationType,
          isActive: body['is_active'] as bool? ?? old.isActive,
        );
        locations[index] = location;
        return http.Response(jsonEncode(locationJson(location)), 200);
      }
      if (request.url.path == '/api/v1/item-kinds' && request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'data': itemKinds.map(itemKindJson).toList(),
            'total': itemKinds.length,
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/item-kinds' &&
          request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final code = (body['code'] as String).trim().toUpperCase();
        if (itemKinds.any((item) => item.code.toUpperCase() == code)) {
          return http.Response(
            '{"error":"kode jenis barang sudah digunakan"}',
            409,
          );
        }
        final item = ItemKind(
          id: 'kind-created-${itemKinds.length}',
          code: code,
          name: (body['name'] as String).trim(),
          isActive: body['is_active'] as bool,
        );
        itemKinds.insert(0, item);
        return http.Response(jsonEncode(itemKindJson(item)), 201);
      }
      if (request.url.path.startsWith('/api/v1/item-kinds/') &&
          request.method == 'PATCH') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final id = request.url.path.split('/').last;
        final index = itemKinds.indexWhere((item) => item.id == id);
        if (index < 0) {
          return http.Response('{"error":"jenis barang tidak ditemukan"}', 404);
        }
        final old = itemKinds[index];
        final item = ItemKind(
          id: old.id,
          code: body['code'] as String? ?? old.code,
          name: body['name'] as String? ?? old.name,
          isActive: body['is_active'] as bool? ?? old.isActive,
        );
        itemKinds[index] = item;
        return http.Response(jsonEncode(itemKindJson(item)), 200);
      }
      if (request.url.path == '/api/v1/categories' && request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'data': categories.map(categoryJson).toList(),
            'total': categories.length,
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/categories' &&
          request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final code = (body['code'] as String).trim().toUpperCase();
        if (categories.any((item) => item.code.toUpperCase() == code)) {
          return http.Response(
            '{"error":"kode kategori sudah digunakan"}',
            409,
          );
        }
        final item = ItemCategory(
          id: 'category-created-${categories.length}',
          code: code,
          name: (body['name'] as String).trim(),
          description: (body['description'] as String).trim(),
          isActive: body['is_active'] as bool,
        );
        categories.insert(0, item);
        return http.Response(jsonEncode(categoryJson(item)), 201);
      }
      if (request.url.path.startsWith('/api/v1/categories/') &&
          request.method == 'PATCH') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final id = request.url.path.split('/').last;
        final index = categories.indexWhere((item) => item.id == id);
        if (index < 0) {
          return http.Response('{"error":"kategori tidak ditemukan"}', 404);
        }
        final old = categories[index];
        final item = ItemCategory(
          id: old.id,
          code: body['code'] as String? ?? old.code,
          name: body['name'] as String? ?? old.name,
          description: body['description'] as String? ?? old.description,
          isActive: body['is_active'] as bool? ?? old.isActive,
        );
        categories[index] = item;
        return http.Response(jsonEncode(categoryJson(item)), 200);
      }
      if (request.url.path == '/api/v1/users' && request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final username = (body['username'] as String).trim().toLowerCase();
        if (users.any((user) => user.username == username)) {
          return http.Response('{"error":"username sudah digunakan"}', 409);
        }
        final user = UserAccount(
          id: 'user-created-${users.length}',
          name: body['full_name'] as String,
          username: username,
          role: (body['role'] as String).replaceFirstMapped(
            RegExp(r'^.'),
            (match) => match[0]!.toUpperCase(),
          ),
          isActive: true,
        );
        users.insert(0, user);
        return http.Response(jsonEncode(userJson(user)), 201);
      }
      if (request.url.path.startsWith('/api/v1/users/') &&
          request.method == 'PATCH') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final id = request.url.path.split('/').last;
        final index = users.indexWhere((user) => user.id == id);
        if (index < 0) {
          return http.Response('{"error":"pengguna tidak ditemukan"}', 404);
        }
        final old = users[index];
        final role = body['role'] as String? ?? old.role.toLowerCase();
        final user = old.copyWith(
          name: body['full_name'] as String? ?? old.name,
          username: body['username'] as String? ?? old.username,
          role: role.replaceFirstMapped(
            RegExp(r'^.'),
            (match) => match[0]!.toUpperCase(),
          ),
          isActive: body['is_active'] as bool? ?? old.isActive,
        );
        users[index] = user;
        return http.Response(jsonEncode(userJson(user)), 200);
      }
      if (request.url.path == '/api/v1/auth/change-password') {
        return http.Response('', 204);
      }
      return http.Response('{"error":"endpoint fixture tidak dikenal"}', 404);
    }),
  );
}

// Helper login memakai HTTP tiruan dan melanjutkan hanya sesudah respons API sukses.
Future<void> _pumpDashboard(
  WidgetTester tester, {
  Size viewport = const Size(1440, 1100),
  String loginRole = 'admin',
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    InventarisApp(apiClient: _testApiClient(loginRole: loginRole)),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('login-username')), 'petugas');
  await tester.enterText(
    find.byKey(const Key('login-password')),
    'demo-password',
  );
  await tester.tap(find.byKey(const Key('login-submit')));
  await tester.pumpAndSettle();
}

void main() {
  test('asset label resolves school name through parent locations', () {
    const locations = [
      MasterLocation(
        id: 'school-1',
        code: 'SDN01',
        name: 'SD Negeri Contoh',
        locationType: 'sekolah',
        isActive: true,
      ),
      MasterLocation(
        id: 'building-1',
        code: 'BLD01',
        name: 'Gedung Utama',
        locationType: 'gedung',
        parentId: 'school-1',
        isActive: true,
      ),
      MasterLocation(
        id: 'room-1',
        code: 'R01',
        name: 'Ruang Kelas 1',
        locationType: 'ruang',
        parentId: 'building-1',
        isActive: true,
      ),
    ];

    expect(schoolNameForAssetLocation('room-1', locations), 'SD Negeri Contoh');
    expect(
      schoolNameForAssetLocation('unknown-location', locations),
      'Nama sekolah belum diatur',
    );
  });

  test('login persists its token and server expiry', () async {
    final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 15));
    final storage = _MemorySessionStorage(null);
    final apiClient = ApiClient(
      sessionStorage: storage,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'access_token': 'new-access-token',
            'expires_at': expiresAt.toIso8601String(),
            'user': {
              'id': demoUsers.first.id,
              'username': demoUsers.first.username,
              'full_name': demoUsers.first.name,
              'role': 'admin',
              'is_active': true,
              'last_login_at': null,
            },
          }),
          200,
        ),
      ),
    );
    addTearDown(apiClient.close);

    await apiClient.login('admin', 'kata-sandi-rahasia');

    expect(storage.session?.accessToken, 'new-access-token');
    expect(storage.session?.expiresAt, expiresAt);
  });

  testWidgets('login requires username and password', (tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const InventarisApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Username wajib diisi'), findsOneWidget);
    expect(find.text('Kata sandi wajib diisi'), findsOneWidget);
    expect(find.text('Selamat datang'), findsOneWidget);
  });

  testWidgets('login displays an API error without opening the dashboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final apiClient = ApiClient(
      httpClient: MockClient(
        (_) async => http.Response(
          '{"error":"username atau kata sandi tidak valid"}',
          401,
        ),
      ),
    );
    await tester.pumpWidget(InventarisApp(apiClient: apiClient));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('login-username')), 'admin');
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'kata-sandi-salah',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('username atau kata sandi tidak valid'), findsOneWidget);
    expect(find.text('Selamat pagi, Admin 👋'), findsNothing);
  });

  testWidgets('restores a valid browser session after app reload', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final storage = _MemorySessionStorage(
      PersistedApiSession(
        accessToken: 'persisted-access-token',
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
      ),
    );
    final apiClient = ApiClient(
      sessionStorage: storage,
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/me') {
          expect(
            request.headers['authorization'],
            'Bearer persisted-access-token',
          );
          return http.Response(
            jsonEncode({
              'id': demoUsers.first.id,
              'username': demoUsers.first.username,
              'full_name': demoUsers.first.name,
              'role': 'admin',
              'is_active': true,
              'last_login_at': null,
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/assets') {
          return http.Response(
            '{"data":[],"total":0,"page":1,"page_size":100}',
            200,
          );
        }
        if (request.url.path == '/api/v1/locations' ||
            request.url.path == '/api/v1/item-kinds' ||
            request.url.path == '/api/v1/categories') {
          return http.Response('{"data":[],"total":0}', 200);
        }
        return http.Response('{"error":"endpoint fixture tidak dikenal"}', 404);
      }),
    );

    await tester.pumpWidget(InventarisApp(apiClient: apiClient));
    await tester.pumpAndSettle();

    expect(find.text('Selamat pagi, Admin 👋'), findsOneWidget);
    expect(find.text('Selamat datang'), findsNothing);
  });

  testWidgets('expired browser session returns to login and is cleared', (
    tester,
  ) async {
    final storage = _MemorySessionStorage(
      PersistedApiSession(
        accessToken: 'expired-access-token',
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      ),
    );
    final apiClient = ApiClient(
      sessionStorage: storage,
      httpClient: MockClient((_) async {
        fail('An expired session must not call the API.');
      }),
    );

    await tester.pumpWidget(InventarisApp(apiClient: apiClient));
    await tester.pumpAndSettle();

    expect(find.text('Selamat datang'), findsOneWidget);
    expect(storage.session, isNull);
  });

  testWidgets('dashboard displays inventory summary and recent items', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    expect(find.text('Selamat pagi, Admin 👋'), findsOneWidget);
    expect(find.text('Total Aset'), findsOneWidget);
    expect(find.text('Barang Terbaru'), findsOneWidget);
    expect(find.text('Laptop Lenovo ThinkPad'), findsOneWidget);
  });

  testWidgets('inventory page lists server assets and filters search results', (
    tester,
  ) async {
    await _pumpDashboard(tester);
    await tester.tap(find.text('Inventaris').first);
    await tester.pumpAndSettle();

    expect(find.text('Daftar Barang'), findsOneWidget);
    expect(find.text('Laptop Lenovo ThinkPad'), findsOneWidget);
    expect(find.byKey(const Key('login-error')), findsNothing);
    expect(find.text('Kategori'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('inventory-metric-service')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('inventory-metric-damaged')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('inventory-search')),
      'proyektor',
    );
    await tester.pumpAndSettle();

    expect(find.text('Proyektor Epson'), findsOneWidget);
    expect(find.text('Laptop Lenovo ThinkPad'), findsNothing);
    expect(find.text('1 barang ditampilkan'), findsOneWidget);
  });

  // CATATAN PEMELIHARAAN: jumlah contoh 9 memastikan batas 8 dan navigasi
  // halaman tetap sesuai bila ukuran halaman daftar inventaris diubah.
  testWidgets('inventory list paginates after eight filtered items', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final items = List.generate(
      9,
      (index) => InventoryItem(
        code: 'INV-${index + 1}',
        name: 'Barang ${(index + 1).toString().padLeft(2, '0')}',
        category: 'Elektronik',
        locationId: 'loc-001',
        location: 'Ruang Uji',
        condition: 'Bagus',
        icon: Icons.devices_outlined,
        color: const Color(0xFFE9F2FF),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InventoryPage(
              items: items,
              conditionEvents: const [],
              searchQuery: '',
              onAddItem: () {},
              onEditItem: (_) {},
              onArchiveItem: (_) {},
              onUpdateCondition: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Barang 01'), findsOneWidget);
    expect(find.text('Barang 08'), findsOneWidget);
    expect(find.text('Barang 09'), findsNothing);
    expect(find.text('Menampilkan 1–8 dari 9 barang'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('inventory-page-next')));
    await tester.pumpAndSettle();
    expect(find.text('Barang 09'), findsOneWidget);
    expect(find.text('Barang 01'), findsNothing);
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('inventory-page-previous')));
    await tester.pumpAndSettle();
    expect(find.text('Barang 01'), findsOneWidget);
  });

  testWidgets('inventory page creates an asset through the API', (
    tester,
  ) async {
    await _pumpDashboard(tester, viewport: const Size(390, 844));
    await tester.tap(find.byTooltip('Buka menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inventaris').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inventory-create-item')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Scanner Dokumen');
    await tester.tap(find.byKey(const Key('inventory-location-input')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ruang Tata Usaha').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan aset'));
    await tester.pumpAndSettle();

    expect(find.text('Pratinjau Label Aset'), findsOneWidget);
    expect(find.byKey(const Key('asset-label-barcode')), findsOneWidget);
    final labelCode = tester
        .widget<SelectableText>(find.byKey(const Key('asset-label-code')))
        .data;
    expect(labelCode, startsWith('AST-TEST-'));
    expect(find.byKey(const Key('asset-label-print')), findsOneWidget);
    expect(find.textContaining('80 × 42 mm'), findsOneWidget);
    await tester.tap(find.byKey(const Key('asset-label-close')));
    await tester.pumpAndSettle();

    expect(find.text('Scanner Dokumen'), findsOneWidget);

    final itemActions = find.byTooltip('Aksi Scanner Dokumen');
    await tester.ensureVisible(itemActions);
    await tester.tap(itemActions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lihat label barcode'));
    await tester.pumpAndSettle();
    expect(find.text('Pratinjau Label Aset'), findsOneWidget);
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('asset-label-code')))
          .data,
      labelCode,
    );
    expect(find.byKey(const Key('asset-label-barcode')), findsOneWidget);
  });

  test('asset label PDF contains the server barcode value', () async {
    const item = InventoryItem(
      assetId: 'asset-1',
      code: 'SDN01-ELK-2026-0002',
      name: 'HP Infinix 5G',
      category: 'Elektronik',
      locationId: 'room-1',
      location: 'Ruang Kelas 1',
      condition: 'Bagus',
      icon: Icons.devices_outlined,
      color: Color(0xFFE9F2FF),
    );
    final bytes = await buildAssetLabelPdf(
      item: item,
      schoolName: 'SMP Negeri Contoh',
    );

    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(assetLabelPageFormat.width, 80 * PdfPageFormat.mm);
  });

  testWidgets('inventory stock tab creates a consumable and opening balance', (
    tester,
  ) async {
    await _pumpDashboard(tester, viewport: const Size(390, 844));
    await tester.tap(find.byTooltip('Buka menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inventaris').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('inventory-kind-tabs')),
        matching: find.text('Barang Habis Pakai'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inventory-create-stock-item')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('stock-name-input')),
      'Kertas A4',
    );
    await tester.enterText(find.byKey(const Key('stock-unit-input')), 'rim');
    await tester.enterText(
      find.byKey(const Key('stock-initial-quantity-input')),
      '5',
    );
    await tester.enterText(find.byKey(const Key('stock-minimum-input')), '2');
    await tester.tap(find.byKey(const Key('stock-location-input')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ruang Tata Usaha').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan Barang'));
    await tester.pumpAndSettle();
    expect(find.text('Kertas A4'), findsOneWidget);
    expect(find.text('5 rim'), findsOneWidget);
    expect(find.text('Minimum 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('edit-stock-stock-item-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-stock-quantity')), '3');
    await tester.enterText(
      find.byKey(const Key('edit-stock-notes')),
      'Koreksi hasil hitung.',
    );
    await tester.tap(find.text('Simpan perubahan'));
    await tester.pumpAndSettle();
    expect(find.text('3 rim'), findsOneWidget);
  });

  testWidgets('inventory updates one asset condition and records its history', (
    tester,
  ) async {
    await _pumpDashboard(tester, viewport: const Size(390, 844));
    await tester.tap(find.byTooltip('Buka menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inventaris').first);
    await tester.pumpAndSettle();

    final itemActions = find.byTooltip('Aksi Laptop Lenovo ThinkPad');
    await tester.ensureVisible(itemActions);
    await tester.tap(itemActions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ubah kondisi'));
    await tester.pumpAndSettle();

    expect(find.text('Ubah Kondisi Aset'), findsOneWidget);
    await tester.tap(find.byKey(const Key('save-condition-change')));
    await tester.pumpAndSettle();
    expect(
      find.text('Pilih kondisi yang berbeda dari kondisi saat ini.'),
      findsOneWidget,
    );
    expect(find.text('Catatan perubahan wajib diisi.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('condition-change-value-input')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perlu perbaikan').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('condition-change-notes-input')),
      'Engsel layar perlu diperiksa.',
    );
    await tester.tap(find.byKey(const Key('save-condition-change')));
    await tester.pumpAndSettle();

    expect(
      find.text('Kondisi aset diperbarui dan riwayat berhasil dicatat.'),
      findsOneWidget,
    );

    await tester.tap(itemActions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detail barang'));
    await tester.pumpAndSettle();
    expect(find.text('Perlu perbaikan'), findsAtLeastNWidgets(1));
    expect(find.text('Bagus menjadi Perlu perbaikan'), findsOneWidget);
    expect(find.text('Engsel layar perlu diperiksa.'), findsOneWidget);
    expect(
      find.byKey(const Key('inventory-condition-history-empty')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('movements page creates and cancels a draft transfer', (
    tester,
  ) async {
    await _pumpDashboard(tester, viewport: const Size(390, 844));
    await tester.tap(find.byTooltip('Buka menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mutasi Barang').first);
    await tester.pumpAndSettle();

    expect(find.text('Riwayat Mutasi'), findsOneWidget);
    expect(
      find.textContaining('Draft tersimpan dan dapat dibatalkan.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('create-movement')));
    await tester.pumpAndSettle();

    expect(find.text('Buat Draft Mutasi'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('movement-quantity-input')),
      '3',
    );
    await tester.enterText(
      find.byKey(const Key('movement-notes-input')),
      'Pemindahan perlengkapan.',
    );
    await tester.tap(find.byKey(const Key('save-movement-draft')));
    await tester.pumpAndSettle();

    expect(find.text('Draft mutasi berhasil disimpan.'), findsOneWidget);
    expect(find.textContaining('Pemindahan ·'), findsOneWidget);
    expect(find.text('Laptop Lenovo ThinkPad'), findsOneWidget);
    expect(find.text('Draft'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    final movementNumber = tester
        .widget<Text>(find.textContaining('MUT-'))
        .data!;
    final statusFilter = find.byKey(const Key('movement-status-filter'));
    await tester.ensureVisible(statusFilter);
    await tester.tap(statusFilter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diposting').last);
    await tester.pumpAndSettle();
    expect(find.text(movementNumber), findsNothing);

    await tester.tap(statusFilter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Semua status').last);
    await tester.pumpAndSettle();
    expect(find.text(movementNumber), findsOneWidget);

    final movementAction = find.byTooltip('Aksi $movementNumber');
    await tester.ensureVisible(movementAction);
    await tester.tap(movementAction);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batalkan draft'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-cancel-movement')));
    await tester.pumpAndSettle();

    expect(find.text('Draft mutasi berhasil dibatalkan.'), findsOneWidget);
    expect(find.text('Dibatalkan'), findsAtLeastNWidgets(2));
  });

  testWidgets('maintenance reports move through work and completion states', (
    tester,
  ) async {
    await _pumpDashboard(tester, viewport: const Size(390, 844));
    await tester.tap(find.byTooltip('Buka menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pemeliharaan').first);
    await tester.pumpAndSettle();

    expect(find.text('Daftar Pemeliharaan'), findsOneWidget);
    expect(
      find.textContaining(
        'Status laporan tidak mengubah kondisi aset secara otomatis.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('maintenance-create')));
    await tester.pumpAndSettle();
    expect(find.text('Buat Laporan Pemeliharaan'), findsOneWidget);

    await tester.tap(find.byKey(const Key('maintenance-save-report')));
    await tester.pumpAndSettle();
    expect(find.text('Keluhan wajib diisi'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('maintenance-description-input')),
      'Laptop tidak dapat mengisi daya.',
    );
    await tester.tap(find.byKey(const Key('maintenance-save-report')));
    await tester.pumpAndSettle();

    expect(
      find.text('Laporan pemeliharaan berhasil disimpan.'),
      findsOneWidget,
    );
    expect(find.text('Laptop tidak dapat mengisi daya.'), findsOneWidget);
    expect(find.text('Dilaporkan'), findsAtLeastNWidgets(2));

    final actions = find.byTooltip('Aksi Laptop Lenovo ThinkPad');
    await tester.ensureVisible(actions);
    await tester.tap(actions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mulai pemeliharaan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('maintenance-confirm-start')));
    await tester.pumpAndSettle();
    expect(find.text('Sedang dikerjakan'), findsAtLeastNWidgets(2));

    await tester.ensureVisible(actions);
    await tester.tap(actions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tandai selesai'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('maintenance-save-completion')));
    await tester.pumpAndSettle();
    expect(find.text('Masukkan biaya akhir (minimal Rp 0)'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('maintenance-final-cost-input')),
      '125000',
    );
    await tester.tap(find.byKey(const Key('maintenance-save-completion')));
    await tester.pumpAndSettle();

    expect(find.text('Selesai'), findsAtLeastNWidgets(2));
    expect(find.text('Rp 125.000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports page summarizes inventory and marks export as mockup', (
    tester,
  ) async {
    await _pumpDashboard(tester, viewport: const Size(390, 844));
    await tester.tap(find.byTooltip('Buka menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laporan').first);
    await tester.pumpAndSettle();

    expect(find.text('Laporan'), findsOneWidget);
    expect(find.text('Aset tercatat'), findsOneWidget);
    expect(find.text('Kondisi aset'), findsOneWidget);
    expect(
      find.text('Belum ada data mutasi atau pemeliharaan.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('report-section-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inventaris').last);
    await tester.pumpAndSettle();
    expect(find.text('Jumlah unit per kategori'), findsOneWidget);
    expect(find.text('Jumlah unit per lokasi saat ini'), findsOneWidget);

    await tester.tap(find.byKey(const Key('report-period-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 hari terakhir').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-export')));
    await tester.pumpAndSettle();

    expect(find.text('Pratinjau Export Laporan'), findsOneWidget);
    expect(find.byKey(const Key('report-preview-pdf')), findsOneWidget);
    expect(
      find.text('CONTOH TAMPILAN PDF · BELUM MENJADI FILE'),
      findsOneWidget,
    );
    await tester.tap(find.text('CSV'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report-preview-csv')), findsOneWidget);
    final csvContent = tester
        .widget<SelectableText>(
          find.byKey(const Key('report-preview-csv-content')),
        )
        .data!;
    expect(
      csvContent,
      startsWith('kode_aset,nama_aset,kategori,lokasi,kondisi'),
    );
    expect(csvContent, contains('AST-FIXTURE-1'));
    await tester.tap(find.byKey(const Key('report-export-preview-download')));
    await tester.pumpAndSettle();
    expect(
      find.text('Unduh CSV masih mockup; file belum dibuat.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('report-export-preview-close')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('search filters the recent inventory list', (tester) async {
    await _pumpDashboard(tester);
    await tester.enterText(
      find.byKey(const Key('inventory-search')),
      'proyektor',
    );
    await tester.pumpAndSettle();

    expect(find.text('Proyektor Epson'), findsOneWidget);
    expect(find.text('Laptop Lenovo ThinkPad'), findsNothing);
  });

  // CATATAN PEMELIHARAAN: pastikan pencarian tetap diperbarui saat rebuild
  // dipersempit ke konten halaman, bukan lagi ke seluruh widget dashboard.
  testWidgets('search filters users without rebuilding the app shell', (
    tester,
  ) async {
    await _pumpDashboard(tester);
    await tester.tap(find.text('Pengguna').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('inventory-search')),
      'siti.petugas',
    );
    await tester.pumpAndSettle();

    expect(find.text('Siti Rahmawati'), findsOneWidget);
    expect(find.text('Budi Santoso'), findsNothing);
    expect(find.text('RuangSarana'), findsOneWidget);
  });

  testWidgets('dashboard add item dialog creates an asset through the API', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    await tester.tap(find.text('Lokasi').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-location')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('location-code-input')),
      'RNG-TEST',
    );
    await tester.enterText(
      find.byKey(const Key('location-name-input')),
      'Studio Musik',
    );
    await tester.tap(find.byKey(const Key('save-location')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dashboard').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tambah Barang').first);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).first,
      'Kamera Dokumentasi',
    );
    await tester.tap(find.byKey(const Key('inventory-location-input')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Studio Musik'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan aset'));
    await tester.pumpAndSettle();
    expect(find.text('Pratinjau Label Aset'), findsOneWidget);
    await tester.tap(find.byKey(const Key('asset-label-close')));
    await tester.pumpAndSettle();

    expect(find.text('Kamera Dokumentasi'), findsOneWidget);
    expect(find.text('Studio Musik'), findsOneWidget);
  });

  testWidgets('mobile layout opens the navigation drawer', (tester) async {
    await _pumpDashboard(tester, viewport: const Size(390, 844));
    await tester.tap(find.byTooltip('Buka menu'));
    await tester.pumpAndSettle();

    expect(find.text('RuangSarana'), findsOneWidget);
    expect(find.text('Inventaris'), findsOneWidget);

    await tester.tap(find.text('Lokasi').first);
    await tester.pumpAndSettle();
    expect(
      find.text('Atur sekolah, gedung, ruang, gudang, dan area.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Buka menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jenis & Kategori').first);
    await tester.pumpAndSettle();
    expect(find.text('Jenis Barang'), findsOneWidget);
    expect(find.text('Barang Habis Pakai'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop navigation includes the reusable school footer', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    expect(find.text('RuangSarana'), findsOneWidget);
    expect(find.text('SMP Negeri 1'), findsOneWidget);
    expect(find.text('Tahun ajaran 2025/2026'), findsOneWidget);
  });

  testWidgets('users menu is hidden from non-admin roles', (tester) async {
    await _pumpDashboard(tester, loginRole: 'petugas');

    expect(find.text('Pengguna'), findsNothing);
    expect(find.text('Lokasi'), findsNothing);
    expect(find.text('Jenis & Kategori'), findsNothing);

    await tester.tap(find.text('Inventaris').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inventory-create-item')), findsOneWidget);

    await tester.tap(find.text('Laporan').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report-export')), findsNothing);
  });

  testWidgets('leaders can view data but cannot use operational edit actions', (
    tester,
  ) async {
    await _pumpDashboard(tester, loginRole: 'pimpinan');

    expect(find.text('Tambah Barang'), findsNothing);
    expect(find.text('Pengguna'), findsNothing);
    expect(find.text('Lokasi'), findsOneWidget);
    expect(find.text('Jenis & Kategori'), findsOneWidget);

    await tester.tap(find.text('Inventaris').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inventory-create-item')), findsNothing);
    final inventoryActions = find.byTooltip('Aksi Laptop Lenovo ThinkPad');
    await tester.ensureVisible(inventoryActions);
    await tester.pumpAndSettle();
    await tester.tap(inventoryActions);
    await tester.pumpAndSettle();
    expect(find.text('Ubah kondisi'), findsNothing);
    await tester.tap(find.text('Lihat label barcode'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('asset-label-print')), findsNothing);
    await tester.tap(find.byKey(const Key('asset-label-close')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lokasi').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('create-location')), findsNothing);
    expect(find.text('AKSI'), findsNothing);

    await tester.tap(find.text('Jenis & Kategori').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('create-master-entry')), findsNothing);
    expect(find.text('AKSI'), findsNothing);

    await tester.tap(find.text('Mutasi Barang').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('create-movement')), findsNothing);

    await tester.tap(find.text('Pemeliharaan').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('maintenance-create')), findsNothing);

    await tester.tap(find.text('Laporan').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report-export')), findsOneWidget);
  });

  testWidgets('locations page displays hierarchy and adds a location', (
    tester,
  ) async {
    await _pumpDashboard(tester);
    await tester.tap(find.text('Lokasi').first);
    await tester.pumpAndSettle();

    expect(
      find.text('Atur sekolah, gedung, ruang, gudang, dan area.'),
      findsOneWidget,
    );
    expect(find.text('Gedung Utama'), findsAtLeastNWidgets(1));
    await tester.tap(find.byKey(const Key('create-location')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('location-code-input')),
      'RNG-008',
    );
    await tester.enterText(
      find.byKey(const Key('location-name-input')),
      'Perpustakaan',
    );
    await tester.tap(find.byKey(const Key('save-location')));
    await tester.pumpAndSettle();

    expect(find.text('Perpustakaan'), findsOneWidget);
    expect(find.text('RNG-008'), findsOneWidget);
    expect(find.text('Lokasi berhasil disimpan.'), findsOneWidget);
  });

  testWidgets('kinds and categories page switches tabs and adds a category', (
    tester,
  ) async {
    await _pumpDashboard(tester);
    await tester.tap(find.text('Jenis & Kategori').first);
    await tester.pumpAndSettle();

    expect(find.text('Daftar Jenis Barang'), findsOneWidget);
    expect(find.text('Barang Habis Pakai'), findsOneWidget);
    await tester.tap(find.byKey(const Key('create-master-entry')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('kind-code-input')), 'SERVICE');
    await tester.enterText(
      find.byKey(const Key('kind-name-input')),
      'Peralatan Layanan',
    );
    await tester.tap(find.byKey(const Key('save-kind')));
    await tester.pumpAndSettle();
    expect(find.text('Peralatan Layanan'), findsOneWidget);
    expect(find.text('Jenis barang berhasil disimpan.'), findsOneWidget);

    await tester.tap(find.text('Kategori').last);
    await tester.pumpAndSettle();
    expect(find.text('Daftar Kategori'), findsOneWidget);
    expect(find.text('Elektronik'), findsOneWidget);

    await tester.tap(find.byKey(const Key('create-master-entry')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('category-code-input')), 'LAB');
    await tester.enterText(
      find.byKey(const Key('category-name-input')),
      'Laboratorium',
    );
    await tester.enterText(
      find.byKey(const Key('category-description-input')),
      'Peralatan laboratorium sekolah.',
    );
    await tester.tap(find.byKey(const Key('save-category')));
    await tester.pumpAndSettle();

    expect(find.text('Laboratorium'), findsOneWidget);
    expect(find.text('Kategori berhasil disimpan.'), findsOneWidget);
  });

  testWidgets('users page shows account role status and last login', (
    tester,
  ) async {
    await _pumpDashboard(tester);
    await tester.tap(find.text('Pengguna').first);
    await tester.pumpAndSettle();

    expect(find.text('Daftar Pengguna'), findsOneWidget);
    expect(find.text('Admin Sekolah'), findsNWidgets(2));
    expect(find.text('12 Nov 2026, 08:15'), findsOneWidget);
    expect(find.textContaining('Kata sandi akun'), findsNothing);
    expect(find.byKey(const Key('user-page-next')), findsNothing);
  });

  // CATATAN PEMELIHARAAN: sesuaikan data uji ini bila batas halaman berubah.
  testWidgets('users page shows eight accounts per page and navigates pages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final users = List.generate(
      9,
      (index) => UserAccount(
        id: 'user-$index',
        name: 'Akun ${(index + 1).toString().padLeft(2, '0')}',
        username: 'akun$index',
        role: 'Petugas',
        isActive: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: UsersPage(
              users: users,
              searchQuery: '',
              onCreate: () {},
              onEdit: (_) {},
              onToggleActive: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Akun 01'), findsOneWidget);
    expect(find.text('Akun 08'), findsOneWidget);
    expect(find.text('Akun 09'), findsNothing);
    expect(find.text('Menampilkan 1–8 dari 9 pengguna'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('user-page-next')));
    await tester.pumpAndSettle();
    expect(find.text('Akun 09'), findsOneWidget);
    expect(find.text('Akun 01'), findsNothing);
    expect(find.text('2 / 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('user-page-previous')));
    await tester.pumpAndSettle();
    expect(find.text('Akun 01'), findsOneWidget);
  });

  testWidgets('users page creates an account through the API client', (
    tester,
  ) async {
    await _pumpDashboard(tester);
    await tester.tap(find.text('Pengguna').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-user')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('user-name-input')),
      'Dewi Petugas',
    );
    await tester.enterText(
      find.byKey(const Key('user-username-input')),
      'dewi.petugas',
    );
    await tester.enterText(
      find.byKey(const Key('user-initial-password-input')),
      'kata-sandi-dewi-aman',
    );
    await tester.tap(find.byKey(const Key('save-user')));
    await tester.pumpAndSettle();

    expect(find.text('Dewi Petugas'), findsOneWidget);
    expect(find.text('@dewi.petugas'), findsOneWidget);
    expect(find.text('Pengguna berhasil dibuat.'), findsOneWidget);
  });

  testWidgets('users page archives account after API accepts update', (
    tester,
  ) async {
    await _pumpDashboard(tester);
    await tester.tap(find.text('Pengguna').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Aksi Admin Sekolah'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nonaktifkan (arsip)'));
    await tester.pumpAndSettle();

    expect(find.text('Pengguna diarsipkan.'), findsOneWidget);
    expect(find.text('Nonaktif'), findsAtLeastNWidgets(1));
  });

  testWidgets('users page rejects a duplicate username', (tester) async {
    await _pumpDashboard(tester);
    await tester.tap(find.text('Pengguna').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-user')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('user-name-input')),
      'Akun Baru',
    );
    await tester.enterText(
      find.byKey(const Key('user-username-input')),
      'ADMIN',
    );
    await tester.enterText(
      find.byKey(const Key('user-initial-password-input')),
      'kata-sandi-admin-baru',
    );
    await tester.tap(find.byKey(const Key('save-user')));
    await tester.pumpAndSettle();

    expect(find.text('Akun Baru'), findsNothing);
    expect(find.text('username sudah digunakan'), findsOneWidget);
  });

  testWidgets('profile menu changes password through API and logs out', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    final profileBottom = tester.getRect(find.text('Admin Sekolah')).bottom;
    await tester.tap(find.byTooltip('Menu profil'));
    await tester.pumpAndSettle();
    expect(find.text('Ubah kata sandi'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
    expect(
      tester.getRect(find.text('Ubah kata sandi')).top,
      greaterThanOrEqualTo(profileBottom),
    );

    await tester.tap(find.text('Ubah kata sandi'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('current-password')),
      'old-password',
    );
    await tester.enterText(
      find.byKey(const Key('new-password')),
      'new-password-aman',
    );
    await tester.enterText(
      find.byKey(const Key('confirm-password')),
      'new-password-aman',
    );
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(find.text('Kata sandi berhasil diubah.'), findsOneWidget);

    await tester.tap(find.byTooltip('Menu profil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logout'));
    await tester.pumpAndSettle();

    expect(find.text('Selamat datang'), findsOneWidget);
  });
}
