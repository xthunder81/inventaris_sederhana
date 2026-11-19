import 'dart:async';

import 'package:flutter/material.dart';

import 'features/auth/views/change_password_dialog.dart';
import 'features/auth/views/login_page.dart';
import 'features/inventory/models/inventory_item.dart';
import 'features/inventory/models/stock_item.dart';
import 'features/inventory/views/inventory_page.dart';
import 'features/maintenance/models/maintenance_record.dart';
import 'features/maintenance/views/maintenance_page.dart';
import 'features/master_data/models/master_data.dart';
import 'features/master_data/views/item_kinds_categories_page.dart';
import 'features/master_data/views/locations_page.dart';
import 'features/movements/models/stock_movement.dart';
import 'features/movements/views/movements_page.dart';
import 'features/reports/views/reports_page.dart';
import 'features/users/models/user_account.dart';
import 'features/users/views/users_page.dart';
import 'shared/auth/role_permissions.dart';
import 'shared/services/api_client.dart';
import 'shared/services/session_storage.dart';
import 'shared/widgets/app_header.dart';
import 'shared/widgets/app_navbar.dart';

export 'features/inventory/models/inventory_item.dart';

void main() {
  runApp(const InventarisApp());
}

class InventarisApp extends StatefulWidget {
  const InventarisApp({super.key, this.apiClient});

  final ApiClient? apiClient;

  @override
  State<InventarisApp> createState() => _InventarisAppState();
}

class _InventarisAppState extends State<InventarisApp> {
  late final ApiClient _apiClient = widget.apiClient ?? ApiClient();
  UserAccount? _currentUser;
  bool _isRestoringSession = true;
  String? _sessionRestoreError;

  @override
  void initState() {
    super.initState();
    _apiClient.onUnauthorized = _handleUnauthorized;
    unawaited(_restoreSession());
  }

  // CATATAN PEMELIHARAAN: saat browser dimuat ulang, klien memvalidasi token
  // tersimpan lewat /me; gangguan jaringan ditampilkan sebagai kondisi retry,
  // bukan dianggap sebagai token rusak atau langsung logout.
  Future<void> _restoreSession() async {
    try {
      final user = await _apiClient.restoreSession();
      if (!mounted) return;
      setState(() {
        _currentUser = user;
        _isRestoringSession = false;
        _sessionRestoreError = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isRestoringSession = false;
        _sessionRestoreError = error.message;
      });
    } on SessionStorageException catch (error) {
      if (!mounted) return;
      setState(() {
        _isRestoringSession = false;
        _sessionRestoreError = error.message;
      });
    }
  }

  void _retrySessionRestore() {
    setState(() {
      _isRestoringSession = true;
      _sessionRestoreError = null;
    });
    unawaited(_restoreSession());
  }

  Future<void> _clearSessionAndContinueToLogin() async {
    try {
      await _apiClient.logout();
      if (!mounted) return;
      setState(() {
        _currentUser = null;
        _sessionRestoreError = null;
      });
    } on SessionStorageException catch (error) {
      if (!mounted) return;
      setState(() => _sessionRestoreError = error.message);
    }
  }

  // CATATAN PEMELIHARAAN: token sudah dihapus klien sebelum callback 401 ini;
  // callback hanya menyelaraskan UI dengan sesi yang ditolak server.
  void _handleUnauthorized() {
    if (mounted && _currentUser != null) {
      setState(() => _currentUser = null);
    }
  }

  // CATATAN PEMELIHARAAN: kredensial tidak disimpan; sesi hanya dibuka setelah
  // login API berhasil dan token beserta waktu expiry berhasil disimpan.
  Future<void> _signIn(String username, String password) async {
    final session = await _apiClient.login(username, password);
    if (mounted) {
      setState(() {
        _currentUser = session.user;
        _sessionRestoreError = null;
      });
    }
  }

  Future<void> _signOut() async {
    try {
      await _apiClient.logout();
      if (mounted) setState(() => _currentUser = null);
    } on SessionStorageException catch (error) {
      if (!mounted) return;
      setState(() {
        _currentUser = null;
        _sessionRestoreError = error.message;
      });
    }
  }

  @override
  void dispose() {
    _apiClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF172B4D);
    const teal = Color(0xFF168B83);

    return MaterialApp(
      title: 'RuangSarana',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F8FB),
        colorScheme: ColorScheme.fromSeed(
          seedColor: teal,
          primary: teal,
          surface: Colors.white,
        ),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(
            color: ink,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          titleLarge: TextStyle(
            color: ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          titleMedium: TextStyle(
            color: ink,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          bodyMedium: TextStyle(color: Color(0xFF53627A), fontSize: 13),
          bodySmall: TextStyle(color: Color(0xFF8994A7), fontSize: 12),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7F9FC),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE7EBF1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE7EBF1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: teal, width: 1.5),
          ),
        ),
      ),
      home: _isRestoringSession
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _sessionRestoreError != null
          ? _buildSessionRestoreError()
          : _currentUser != null
          ? InventoryDashboard(
              apiClient: _apiClient,
              currentUser: _currentUser!,
              onLogout: _signOut,
            )
          : LoginPage(onLogin: _signIn),
    );
  }

  Widget _buildSessionRestoreError() {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_clock_outlined,
                  size: 44,
                  color: Color(0xFF168B83),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Sesi belum dapat dipulihkan',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _sessionRestoreError ?? 'Silakan coba lagi.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _retrySessionRestore,
                  child: const Text('Coba lagi'),
                ),
                TextButton(
                  onPressed: _clearSessionAndContinueToLogin,
                  child: const Text('Hapus sesi dan kembali ke login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InventoryDashboard extends StatefulWidget {
  const InventoryDashboard({
    super.key,
    required this.apiClient,
    required this.currentUser,
    required this.onLogout,
  });

  final ApiClient apiClient;
  final UserAccount currentUser;
  final Future<void> Function() onLogout;

  @override
  State<InventoryDashboard> createState() => _InventoryDashboardState();
}

class _InventoryDashboardState extends State<InventoryDashboard> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchController = TextEditingController();
  // CATATAN KINERJA: notifier memperbarui konten hasil pencarian tanpa
  // membangun ulang header, navigasi, dan seluruh dashboard setiap ketikan.
  final _searchQuery = ValueNotifier<String>('');
  List<InventoryItem> _items = [];
  List<StockItem> _stockItems = [];
  bool _isLoadingStockItems = true;
  String? _stockItemsLoadError;
  List<AssetConditionEvent> _conditionEvents = [];
  // CATATAN PEMELIHARAAN: header dan baris mutasi berasal dari API; state
  // diganti hanya setelah server menyimpan atau membatalkan draft.
  final List<StockMovement> _movements = [];
  bool _isLoadingMovements = false;
  bool _movementsLoaded = false;
  String? _movementLoadError;
  // CATATAN PEMELIHARAAN: daftar adalah snapshot API untuk daftar, metrik,
  // pencarian, dan laporan; mutasi lokal hanya diterapkan setelah response.
  List<MaintenanceRecord> _maintenanceRecords = [];
  bool _isLoadingMaintenance = false;
  bool _maintenanceLoaded = false;
  String? _maintenanceLoadError;
  // CATATAN PEMELIHARAAN: lokasi dimuat sekali saat dashboard dibuka dan
  // seluruh perubahan mengganti state hanya setelah API mengonfirmasi sukses.
  // Jika operasi master data berubah, pertahankan error/retry tanpa fallback
  // ke contoh lokal yang bisa disalahartikan sebagai data tersimpan.
  List<MasterLocation> _locations = [];
  bool _isLoadingLocations = true;
  String? _locationLoadError;
  bool _locationsLoaded = false;
  bool _isLoadingAssets = true;
  String? _assetLoadError;
  List<ItemKind> _itemKinds = [];
  List<ItemCategory> _itemCategories = [];
  bool _isLoadingCatalogs = true;
  bool _catalogsLoaded = false;
  String? _catalogLoadError;
  List<UserAccount>? _userList;
  String? _userLoadError;
  bool _isLoadingUsers = false;
  bool _usersLoaded = false;
  List<UserAccount> get _users => _userList ?? const [];
  String _conditionFilter = 'Semua kondisi';
  String _selectedPage = 'Dashboard';
  late final _permissions = RolePermissions.fromRole(widget.currentUser.role);

  @override
  void initState() {
    super.initState();
    unawaited(_loadLocations(showLoading: false));
    unawaited(_loadCatalogs(showLoading: false));
    unawaited(_loadAssets(showLoading: false));
    unawaited(_loadStockItems(showLoading: false));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchQuery.dispose();
    super.dispose();
  }

  // CATATAN: menyaring barang berdasarkan nama/kode/kategori/lokasi dan
  // kondisi aktif; tambahkan atribut di sini jika cakupan pencarian berubah.
  List<InventoryItem> _filterItems(String searchQuery) {
    final query = searchQuery.trim().toLowerCase();
    return _items.where((item) {
      final matchesQuery =
          query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.code.toLowerCase().contains(query) ||
          item.category.toLowerCase().contains(query) ||
          item.location.toLowerCase().contains(query);
      final matchesCondition =
          _conditionFilter == 'Semua kondisi' ||
          item.condition == _conditionFilter;
      return matchesQuery && matchesCondition;
    }).toList();
  }

  // CATATAN MOCKUP: dipakai untuk menu yang belum mempunyai halaman.
  // Ganti notifikasi ini dengan navigasi ke route/halaman saat fitur dibuat.
  void _showComingSoon(String page) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Halaman $page akan dirancang pada tahap berikutnya.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // CATATAN: memilih halaman dan mengosongkan pencarian agar query dari
  // halaman sebelumnya tidak ikut menyaring konten; izin tetap dicek di sini.
  void _selectPage(String page) {
    if (page == 'Pengguna' && !_permissions.canManageUsers) return;
    if (const {'Lokasi', 'Jenis & Kategori'}.contains(page) &&
        !_permissions.canViewMasterData) {
      return;
    }
    setState(() {
      _selectedPage = page;
      _searchController.clear();
      _searchQuery.value = '';
    });
    if (page == 'Pengguna' && !_usersLoaded && !_isLoadingUsers) {
      unawaited(_loadUsers());
    }
    if (page == 'Jenis & Kategori' && !_catalogsLoaded && !_isLoadingCatalogs) {
      unawaited(_loadCatalogs());
    }
    if (const {'Mutasi Barang', 'Laporan'}.contains(page) &&
        !_movementsLoaded &&
        !_isLoadingMovements) {
      unawaited(_loadMovements());
    }
    if (const {'Pemeliharaan', 'Laporan'}.contains(page) &&
        !_maintenanceLoaded &&
        !_isLoadingMaintenance) {
      unawaited(_loadMaintenanceRecords());
    }
    if (!const {
      'Dashboard',
      'Inventaris',
      'Mutasi Barang',
      'Pemeliharaan',
      'Laporan',
      'Pengguna',
      'Lokasi',
      'Jenis & Kategori',
    }.contains(page)) {
      _showComingSoon(page);
    }
  }

  // CATATAN PEMELIHARAAN: kata sandi awal hanya diteruskan ke create endpoint,
  // tidak ditaruh di UserAccount/state. Server meng-hash password dan indeks
  // Mongo menangani username unik; jika server menolak, daftar tidak berubah.
  Future<void> _createUser() async {
    final draft = await showDialog<UserAccountDraft>(
      context: context,
      builder: (context) => const UserAccountDialog(),
    );
    if (draft == null || !mounted) return;
    try {
      final saved = await widget.apiClient.createUser(
        user: draft.user,
        password: draft.initialPassword,
      );
      if (!mounted) return;
      setState(() {
        _userList ??= [];
        _userList!.insert(0, saved);
        _usersLoaded = true;
      });
      _showAppMessage('Pengguna berhasil dibuat.');
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: server mengulang validasi username/peran dan
  // menyimpan patch; state lokal diperbarui hanya setelah response berhasil.
  Future<void> _editUser(UserAccount existingUser) async {
    final draft = await showDialog<UserAccountDraft>(
      context: context,
      builder: (context) => UserAccountDialog(user: existingUser),
    );
    if (draft == null || !mounted) return;
    try {
      final updatedUser = await widget.apiClient.updateUser(draft.user);
      if (!mounted) return;
      setState(() {
        final index = _users.indexWhere((user) => user.id == updatedUser.id);
        if (index >= 0) _users[index] = updatedUser;
      });
      _showAppMessage('Perubahan pengguna disimpan.');
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: nonaktif berarti arsip, bukan hapus; API menyimpan
  // status lalu middleware segera menolak token akun yang telah dinonaktifkan.
  Future<void> _toggleUserActive(UserAccount user) async {
    try {
      final updated = await widget.apiClient.updateUser(
        user.copyWith(isActive: !user.isActive),
      );
      if (!mounted) return;
      setState(() {
        final index = _users.indexWhere((item) => item.id == updated.id);
        if (index >= 0) _users[index] = updated;
      });
      _showAppMessage(
        updated.isActive ? 'Pengguna diaktifkan.' : 'Pengguna diarsipkan.',
      );
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: pemuatan dilakukan sekali saat masuk ke halaman;
  // retry mempertahankan error terlihat dan tidak mengganti kegagalan API
  // dengan data demo yang tampak seolah tersimpan di server.
  Future<void> _loadUsers() async {
    setState(() {
      _isLoadingUsers = true;
      _userLoadError = null;
    });
    try {
      final users = await widget.apiClient.listUsers();
      if (!mounted) return;
      setState(() {
        _userList = users;
        _usersLoaded = true;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _userLoadError = error.message);
    } finally {
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  Future<void> _loadLocations({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoadingLocations = true;
        _locationLoadError = null;
      });
    }
    try {
      final locations = await widget.apiClient.listLocations();
      if (!mounted) return;
      setState(() {
        _locations = locations;
        _locationLoadError = null;
        _locationsLoaded = true;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _locationLoadError = error.message);
    } finally {
      if (mounted) setState(() => _isLoadingLocations = false);
    }
  }

  // CATATAN PEMELIHARAAN: kedua koleksi dimuat sebagai satu state halaman;
  // jika salah satu request gagal, tampilkan error dan retry tanpa mencampur
  // hasil server dengan fixture demo yang terlihat seperti data tersimpan.
  Future<void> _loadCatalogs({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoadingCatalogs = true;
        _catalogLoadError = null;
      });
    }
    try {
      final itemKinds = await widget.apiClient.listItemKinds();
      final categories = await widget.apiClient.listCategories();
      if (!mounted) return;
      setState(() {
        _itemKinds = itemKinds;
        _itemCategories = categories;
        _catalogsLoaded = true;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _catalogLoadError = error.message);
    } finally {
      if (mounted) setState(() => _isLoadingCatalogs = false);
    }
  }

  // CATATAN PEMELIHARAAN: daftar aset dan event diambil bersama saat sesi
  // dashboard dibuka; kegagalan tidak diganti demo. Retry memuat ulang snapshot
  // yang sama agar baris aset dan riwayat tidak berbeda sumber.
  Future<void> _loadAssets({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoadingAssets = true;
        _assetLoadError = null;
      });
    }

    try {
      final snapshot = await widget.apiClient.listAssets();
      if (!mounted) return;
      setState(() {
        _items = snapshot.items;
        _conditionEvents = snapshot.conditionEvents;
        _assetLoadError = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _assetLoadError = error.message);
    } finally {
      if (mounted) setState(() => _isLoadingAssets = false);
    }
  }

  // CATATAN PEMELIHARAAN: daftar saldo barang habis pakai dimuat terpisah
  // dari unit aset; kegagalan tidak menghilangkan data aset dari tab pertama.
  Future<void> _loadStockItems({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoadingStockItems = true;
        _stockItemsLoadError = null;
      });
    }
    try {
      final items = await widget.apiClient.listStockItems();
      if (!mounted) return;
      setState(() {
        _stockItems = items;
        _stockItemsLoadError = null;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _stockItemsLoadError = error.message);
    } finally {
      if (mounted) setState(() => _isLoadingStockItems = false);
    }
  }

  // CATATAN PEMELIHARAAN: API membuat katalog stok dan saldo awal secara
  // berpasangan; UI menambahkannya ke tab stok hanya setelah response sukses.
  Future<void> _createStockItem(StockItemInput input) async {
    try {
      final item = await widget.apiClient.createStockItem(input);
      if (!mounted) return;
      setState(() {
        _stockItems = [..._stockItems, item];
        _stockItemsLoadError = null;
      });
      _showAppMessage('Barang habis pakai dan stok awal berhasil disimpan.');
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: backend menyimpan metadata dan saldo per lokasi;
  // koreksi jumlah juga menghasilkan mutasi adjustment posted untuk audit.
  Future<void> _updateStockItem(StockItemEditInput input) async {
    try {
      final item = await widget.apiClient.updateStockItem(input);
      if (!mounted) return;
      setState(() {
        final index = _stockItems.indexWhere(
          (value) => value.itemId == item.itemId,
        );
        if (index >= 0) _stockItems[index] = item;
      });
      _showAppMessage('Data dan jumlah barang berhasil diperbarui.');
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: daftar draft dan statusnya dimuat saat halaman
  // Mutasi/Laporan dibuka. Kegagalan ditampilkan dan dapat dicoba ulang; tidak
  // ada fallback lokal yang terlihat seperti data tersimpan di server.
  Future<void> _loadMovements() async {
    setState(() {
      _isLoadingMovements = true;
      _movementLoadError = null;
    });
    try {
      final movements = await widget.apiClient.listMovements();
      if (!mounted) return;
      setState(() {
        _movements
          ..clear()
          ..addAll(movements);
        _movementsLoaded = true;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _movementLoadError = error.message);
    } finally {
      if (mounted) setState(() => _isLoadingMovements = false);
    }
  }

  // CATATAN: satu jalur snackbar untuk seluruh aksi dashboard dan data master,
  // agar pesan hasil simpan, validasi, serta arsip tampil konsisten.
  void _showAppMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  // CATATAN PEMELIHARAAN: tentukan create/edit dari ID yang telah diterima
  // server; hanya respons API yang boleh menjadi state baru di halaman master.
  Future<void> _saveLocation(MasterLocation location) async {
    final isNew = !_locations.any((item) => item.id == location.id);
    try {
      final saved = isNew
          ? await widget.apiClient.createLocation(location)
          : await widget.apiClient.updateLocation(location);
      if (!mounted) return;
      setState(() {
        final index = _locations.indexWhere((item) => item.id == saved.id);
        if (index < 0) {
          _locations.insert(0, saved);
        } else {
          _locations[index] = saved;
        }
      });
      _showAppMessage('Lokasi berhasil disimpan.');
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: arsip hanya mengubah status di API dan tidak
  // menghapus lokasi; backend menolak pengarsipan induk yang masih punya anak
  // aktif agar dropdown operasional tidak kehilangan referensi yang dipakai.
  Future<void> _toggleLocationActive(MasterLocation location) async {
    try {
      final updated = await widget.apiClient.updateLocation(
        location.copyWith(isActive: !location.isActive),
      );
      if (!mounted) return;
      setState(() {
        final index = _locations.indexWhere((item) => item.id == updated.id);
        if (index >= 0) _locations[index] = updated;
      });
      _showAppMessage(
        updated.isActive ? 'Lokasi diaktifkan.' : 'Lokasi diarsipkan.',
      );
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: API menentukan ID baru dan menegakkan kode unik;
  // state ditukar hanya setelah response berhasil agar daftar tidak mengklaim
  // perubahan yang belum tersimpan di koleksi item_kinds.
  Future<void> _saveItemKind(ItemKind itemKind) async {
    final isNew = !_itemKinds.any((item) => item.id == itemKind.id);
    try {
      final saved = isNew
          ? await widget.apiClient.createItemKind(itemKind)
          : await widget.apiClient.updateItemKind(itemKind);
      if (!mounted) return;
      setState(() {
        final index = _itemKinds.indexWhere((item) => item.id == saved.id);
        if (index < 0) {
          _itemKinds.insert(0, saved);
        } else {
          _itemKinds[index] = saved;
        }
      });
      _showAppMessage('Jenis barang berhasil disimpan.');
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: arsip mempertahankan record dan referensi katalog
  // lama; backend hanya mengubah is_active setelah Admin diotorisasi.
  Future<void> _toggleItemKind(ItemKind itemKind) async {
    try {
      final updated = await widget.apiClient.updateItemKind(
        itemKind.copyWith(isActive: !itemKind.isActive),
      );
      if (!mounted) return;
      setState(() {
        final index = _itemKinds.indexWhere((item) => item.id == updated.id);
        if (index >= 0) _itemKinds[index] = updated;
      });
      _showAppMessage(
        updated.isActive
            ? 'Jenis barang diaktifkan.'
            : 'Jenis barang diarsipkan.',
      );
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: kategori menyimpan description sendiri, bukan pada
  // item_kinds; backend mewajibkan field ini walau nilainya boleh kosong.
  Future<void> _saveItemCategory(ItemCategory category) async {
    final isNew = !_itemCategories.any((item) => item.id == category.id);
    try {
      final saved = isNew
          ? await widget.apiClient.createCategory(category)
          : await widget.apiClient.updateCategory(category);
      if (!mounted) return;
      setState(() {
        final index = _itemCategories.indexWhere((item) => item.id == saved.id);
        if (index < 0) {
          _itemCategories.insert(0, saved);
        } else {
          _itemCategories[index] = saved;
        }
      });
      _showAppMessage('Kategori berhasil disimpan.');
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: hanya status aktif yang berubah; data dan deskripsi
  // tetap ada agar referensi barang yang sudah tersimpan tetap bermakna.
  Future<void> _toggleItemCategory(ItemCategory category) async {
    try {
      final updated = await widget.apiClient.updateCategory(
        category.copyWith(isActive: !category.isActive),
      );
      if (!mounted) return;
      setState(() {
        final index = _itemCategories.indexWhere(
          (item) => item.id == updated.id,
        );
        if (index >= 0) _itemCategories[index] = updated;
      });
      _showAppMessage(
        updated.isActive ? 'Kategori diaktifkan.' : 'Kategori diarsipkan.',
      );
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: API menetapkan nomor, pelaku, dan waktu; draft lokal
  // baru berubah setelah server menyimpan header dan baris secara berhasil.
  // Endpoint ini tidak menyentuh saldo sampai alur posting atomik tersedia.
  Future<void> _createMovement(StockMovement movement) async {
    try {
      final saved = await widget.apiClient.createMovement(movement);
      if (!mounted) return;
      setState(() {
        _movements.insert(0, saved);
        _movementsLoaded = true;
      });
      _showAppMessage('Draft mutasi berhasil disimpan.');
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: server hanya membatalkan draft dan tidak mengubah
  // saldo; response otoritatif menggantikan record setelah API sukses.
  Future<void> _cancelMovement(StockMovement movement) async {
    if (movement.status != MovementStatus.draft) return;
    try {
      final saved = await widget.apiClient.cancelMovement(movement.id);
      if (!mounted) return;
      setState(() {
        final index = _movements.indexWhere((item) => item.id == saved.id);
        if (index >= 0) _movements[index] = saved;
      });
      _showAppMessage('Draft mutasi berhasil dibatalkan.');
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: hanya response backend yang mengganti status lokal;
  // backend wajib commit saldo, status, dan audit dalam satu transaksi Mongo.
  Future<void> _postMovement(StockMovement movement) async {
    if (movement.status != MovementStatus.draft) return;
    try {
      final saved = await widget.apiClient.postMovement(movement.id);
      if (!mounted) return;
      setState(() {
        final index = _movements.indexWhere((item) => item.id == saved.id);
        if (index >= 0) _movements[index] = saved;
      });
      _showAppMessage('Mutasi berhasil diposting dan saldo stok diperbarui.');
      await _loadStockItems();
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: backend memvalidasi aset/status dan menetapkan
  // waktu/pelapor. Snapshot diganti hanya setelah write berhasil.
  Future<void> _createMaintenanceRecord(MaintenanceRecord record) async {
    try {
      final saved = await widget.apiClient.createMaintenanceRecord(record);
      if (!mounted) return;
      setState(() {
        _maintenanceRecords = [saved, ..._maintenanceRecords];
        _maintenanceLoaded = true;
      });
      _showAppMessage('Laporan pemeliharaan berhasil disimpan.');
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: UI mengirim status tujuan/biaya akhir; API
  // memvalidasi transisi serta menyimpan closed_at. Kondisi aset tetap terpisah.
  Future<void> _updateMaintenanceRecord(MaintenanceRecord updated) async {
    final index = _maintenanceRecords.indexWhere(
      (record) => record.id == updated.id,
    );
    if (index < 0) {
      return;
    }
    final current = _maintenanceRecords[index];
    if (updated.assetId != current.assetId ||
        updated.cost < 0 ||
        !updated.cost.isFinite) {
      return;
    }
    try {
      final saved = await widget.apiClient.updateMaintenanceRecord(updated);
      if (!mounted) return;
      final currentIndex = _maintenanceRecords.indexWhere(
        (record) => record.id == saved.id,
      );
      if (currentIndex >= 0) {
        setState(() => _maintenanceRecords[currentIndex] = saved);
      }
      _showAppMessage(
        'Status pemeliharaan diperbarui: ${maintenanceStatusLabel(saved.status)}.',
      );
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: semua halaman memakai himpunan laporan server yang
  // sama agar metrik laporan dan halaman pemeliharaan tidak berbeda sumber.
  Future<void> _loadMaintenanceRecords() async {
    setState(() {
      _isLoadingMaintenance = true;
      _maintenanceLoadError = null;
    });
    try {
      final records = await widget.apiClient.listMaintenanceRecords();
      if (!mounted) return;
      setState(() {
        _maintenanceRecords = records;
        _maintenanceLoaded = true;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _maintenanceLoadError = error.message);
    } finally {
      if (mounted) setState(() => _isLoadingMaintenance = false);
    }
  }

  // CATATAN PEMELIHARAAN: backend membandingkan kondisi lama per ID aset,
  // menyimpan kondisi baru dan event audit, lalu UI mengganti snapshot hanya
  // setelah response sukses; kesalahan/konflik tidak mengubah state lokal.
  Future<void> _updateItemCondition(
    InventoryItem item,
    AssetConditionEvent event,
  ) async {
    final assetId = item.assetId;
    if (assetId == null) {
      _showAppMessage('ID aset tidak tersedia; perubahan tidak disimpan.');
      return;
    }
    try {
      final snapshot = await widget.apiClient.changeAssetCondition(
        assetId: assetId,
        condition: event.newCondition,
        notes: event.notes,
      );
      if (!mounted) return;
      setState(() {
        final index = _items.indexWhere(
          (candidate) => candidate.assetId == snapshot.items.single.assetId,
        );
        if (index >= 0) _items[index] = snapshot.items.single;
        _conditionEvents.removeWhere(
          (current) => current.assetCode == snapshot.items.single.code,
        );
        _conditionEvents.addAll(snapshot.conditionEvents);
      });
      _showAppMessage('Kondisi aset diperbarui dan riwayat berhasil dicatat.');
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: edit memakai master aktif yang sama dengan form
  // tambah; server menyimpan perubahan per unit dan event audit untuknya.
  Future<void> _editInventoryItem(InventoryItem item) async {
    if (!_catalogsLoaded) await _loadCatalogs();
    if (!_locationsLoaded) await _loadLocations();
    if (!mounted || _catalogLoadError != null || _locationLoadError != null) {
      return;
    }
    final result = await showDialog<InventoryItem>(
      context: context,
      builder: (context) => AddInventoryDialog(
        locations: _locations,
        categories: _itemCategories.where((value) => value.isActive).toList(),
        itemKinds: _itemKinds
            .where(
              (value) =>
                  value.isActive && value.code.toLowerCase() != 'habis_pakai',
            )
            .toList(),
        initialItem: item,
      ),
    );
    if (result == null || !mounted) return;
    try {
      final snapshot = await widget.apiClient.updateAsset(item: result);
      if (!mounted) return;
      final saved = snapshot.items.single;
      setState(() {
        final index = _items.indexWhere(
          (candidate) => candidate.assetId == saved.assetId,
        );
        if (index >= 0) _items[index] = saved;
        _conditionEvents.removeWhere((event) => event.assetCode == saved.code);
        _conditionEvents.addAll(snapshot.conditionEvents);
      });
      _showAppMessage('Data aset berhasil diperbarui.');
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: minta konfirmasi sebelum status aktif diubah.
  // Penghapusan lokal hanya terjadi setelah server mengarsipkan aset sukses.
  Future<void> _archiveInventoryItem(InventoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nonaktifkan aset?'),
        content: Text(
          '${item.name} (${item.code}) tidak akan tampil lagi di daftar aset aktif. Riwayatnya tetap tersimpan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Nonaktifkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || item.assetId == null || !mounted) return;
    try {
      await widget.apiClient.archiveAsset(assetId: item.assetId!);
      if (!mounted) return;
      setState(() {
        _items.removeWhere((value) => value.assetId == item.assetId);
        _conditionEvents.removeWhere((value) => value.assetCode == item.code);
      });
      _showAppMessage('Aset dinonaktifkan. Riwayat tetap tersimpan.');
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: form hanya membuka setelah katalog aktif dimuat.
  // Server membuat barcode dan memvalidasi kategori/lokasi; state berubah
  // setelah penyimpanan sukses. Cetak label tetap pratinjau lokal.
  Future<void> _showAddItemDialog() async {
    if (_isLoadingCatalogs || _isLoadingLocations) {
      _showAppMessage(
        'Data lokasi dan kategori masih dimuat; coba lagi sebentar.',
      );
      return;
    }
    if (!_catalogsLoaded) await _loadCatalogs();
    if (!_locationsLoaded) await _loadLocations();
    if (!mounted) return;
    if (_catalogLoadError != null || _locationLoadError != null) {
      _showAppMessage(
        _catalogLoadError ??
            _locationLoadError ??
            'Data master belum tersedia.',
      );
      return;
    }
    final activeCategories = _itemCategories
        .where((item) => item.isActive)
        .toList();
    if (activeCategories.isEmpty) {
      _showAppMessage('Tambahkan kategori aktif sebelum mencatat aset.');
      return;
    }
    final activeKinds = _itemKinds
        .where(
          (item) => item.isActive && item.code.toLowerCase() != 'habis_pakai',
        )
        .toList();
    if (activeKinds.isEmpty) {
      _showAppMessage(
        'Tambahkan jenis barang aset aktif sebelum mencatat aset.',
      );
      return;
    }
    final result = await showDialog<InventoryItem>(
      context: context,
      builder: (context) => AddInventoryDialog(
        locations: _locations,
        categories: activeCategories,
        itemKinds: activeKinds,
      ),
    );
    if (result == null || !mounted) return;
    final categoryId = result.categoryId;
    if (categoryId == null) {
      _showAppMessage('Kategori aset tidak valid; data tidak disimpan.');
      return;
    }
    try {
      final snapshot = await widget.apiClient.createAsset(
        name: result.name,
        kindId: result.kindId!,
        categoryId: categoryId,
        locationId: result.locationId,
        condition: result.condition,
      );
      if (!mounted) return;
      final saved = snapshot.items.single;
      setState(() {
        _items.insert(0, saved);
        _conditionEvents.addAll(snapshot.conditionEvents);
        _assetLoadError = null;
      });
      _showAppMessage('Aset berhasil disimpan; pratinjau label siap.');
      await showDialog<void>(
        context: context,
        builder: (context) => AssetLabelDialog(
          item: saved,
          schoolName: schoolNameForAssetLocation(saved.locationId, _locations),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) _showAppMessage(error.message);
    }
  }

  // CATATAN PEMELIHARAAN: perubahan disimpan server setelah verifikasi password
  // saat ini; kegagalan kredensial ditampilkan di dialog tanpa mengubah sesi.
  Future<void> _showChangePasswordDialog() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => ChangePasswordDialog(
        onSubmit: (currentPassword, newPassword) =>
            widget.apiClient.changePassword(
              currentPassword: currentPassword,
              newPassword: newPassword,
            ),
      ),
    );
    if (saved != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Kata sandi berhasil diubah.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // CATATAN RESPONSIF: lebar 1080 menentukan shell desktop (navbar
        // tetap) versus shell kecil (navbar masuk ke drawer).
        final isDesktop = constraints.maxWidth >= 1080;
        if (isDesktop) {
          return Scaffold(
            body: Row(
              children: [
                AppNavbar(
                  selectedPage: _selectedPage,
                  onSelect: _selectPage,
                  canManageUsers: _permissions.canManageUsers,
                  canViewMasterData: _permissions.canViewMasterData,
                ),
                Expanded(child: _buildMainContent(isDesktop: true)),
              ],
            ),
          );
        }

        return Scaffold(
          key: _scaffoldKey,
          drawer: Drawer(
            child: AppNavbar(
              selectedPage: _selectedPage,
              canManageUsers: _permissions.canManageUsers,
              canViewMasterData: _permissions.canViewMasterData,
              onSelect: (page) {
                Navigator.pop(context);
                _selectPage(page);
              },
            ),
          ),
          body: _buildMainContent(isDesktop: false),
        );
      },
    );
  }

  Widget _buildMainContent({required bool isDesktop}) {
    return Column(
      children: [
        AppHeader(
          isDesktop: isDesktop,
          searchController: _searchController,
          onSearchChanged: (query) => _searchQuery.value = query,
          onMenuPressed: isDesktop
              ? null
              : () => _scaffoldKey.currentState?.openDrawer(),
          onChangePassword: _showChangePasswordDialog,
          onLogout: widget.onLogout,
          userName: widget.currentUser.name,
          userRole: widget.currentUser.role,
          searchHint: switch (_selectedPage) {
            'Pengguna' => 'Cari nama, username, atau peran...',
            'Lokasi' => 'Cari kode, nama, jenis, atau induk lokasi...',
            'Jenis & Kategori' => 'Cari kode, jenis, atau kategori...',
            'Mutasi Barang' => 'Cari nomor mutasi, barang, atau lokasi...',
            'Pemeliharaan' => 'Cari aset, kode, keluhan, atau status...',
            'Laporan' => 'Cari aset, mutasi, atau catatan pemeliharaan...',
            _ => 'Cari barang, kode, atau lokasi...',
          },
        ),
        if (_selectedPage == 'Dashboard') const _UnconnectedModulesBanner(),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              isDesktop ? 32 : 20,
              28,
              isDesktop ? 32 : 20,
              32,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1500),
                child: _buildSelectedPage(isDesktop: isDesktop),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // CATATAN: peta menu ke konten; pencarian memakai ValueListenableBuilder
  // agar yang dibangun ulang hanya daftar hasil, bukan seluruh shell.
  Widget _buildSelectedPage({required bool isDesktop}) {
    return switch (_selectedPage) {
      'Dashboard' => _buildDashboardPage(isDesktop: isDesktop),
      'Inventaris' => ValueListenableBuilder<String>(
        valueListenable: _searchQuery,
        builder: (context, searchQuery, _) {
          if (_isLoadingAssets) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_isLoadingLocations) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_assetLoadError != null) {
            return _LoadErrorPanel(
              message: _assetLoadError!,
              onRetry: _loadAssets,
            );
          }
          if (_locationLoadError != null) {
            return _LoadErrorPanel(
              message: _locationLoadError!,
              onRetry: _loadLocations,
            );
          }
          return InventoryPage(
            items: _items,
            conditionEvents: _conditionEvents,
            searchQuery: searchQuery,
            onAddItem: _showAddItemDialog,
            onEditItem: _editInventoryItem,
            onArchiveItem: _archiveInventoryItem,
            onUpdateCondition: _updateItemCondition,
            canManageAssets: _permissions.canManageAssets,
            canPrintAssetLabels: _permissions.canPrintAssetLabels,
            stockItems: _stockItems,
            stockCategories: _itemCategories,
            stockKinds: _itemKinds,
            locations: _locations,
            searchQueryForStock: searchQuery,
            onCreateStockItem: _createStockItem,
            onEditStockItem: _updateStockItem,
            stockItemsLoading: _isLoadingStockItems,
            stockItemsError: _stockItemsLoadError,
            onRetryStockItems: _loadStockItems,
          );
        },
      ),
      'Mutasi Barang' => ValueListenableBuilder<String>(
        valueListenable: _searchQuery,
        builder: (context, searchQuery, _) {
          if (_isLoadingMovements) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_movementLoadError != null) {
            return _LoadErrorPanel(
              message: _movementLoadError!,
              onRetry: _loadMovements,
            );
          }
          if (_isLoadingAssets || _isLoadingLocations) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_assetLoadError != null || _locationLoadError != null) {
            return _LoadErrorPanel(
              message: _assetLoadError ?? _locationLoadError!,
              onRetry: () {
                unawaited(_loadAssets());
                unawaited(_loadLocations());
              },
            );
          }
          return MovementsPage(
            movements: _movements,
            items: _items,
            stockItems: _stockItems,
            locations: _locations,
            searchQuery: searchQuery,
            onCreate: _createMovement,
            onCancel: _cancelMovement,
            onPost: _postMovement,
            canManageMovements: _permissions.canManageMovements,
          );
        },
      ),
      'Pemeliharaan' => ValueListenableBuilder<String>(
        valueListenable: _searchQuery,
        builder: (context, searchQuery, _) {
          if (_isLoadingMaintenance) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_maintenanceLoadError != null) {
            return _LoadErrorPanel(
              message: _maintenanceLoadError!,
              onRetry: _loadMaintenanceRecords,
            );
          }
          return MaintenancePage(
            records: _maintenanceRecords,
            items: _items,
            searchQuery: searchQuery,
            onCreate: _createMaintenanceRecord,
            onUpdate: _updateMaintenanceRecord,
            canManageMaintenance: _permissions.canManageMaintenance,
          );
        },
      ),
      'Laporan' => ValueListenableBuilder<String>(
        valueListenable: _searchQuery,
        builder: (context, searchQuery, _) {
          if (_isLoadingMovements) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_movementLoadError != null) {
            return _LoadErrorPanel(
              message: _movementLoadError!,
              onRetry: _loadMovements,
            );
          }
          if (_isLoadingMaintenance) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_maintenanceLoadError != null) {
            return _LoadErrorPanel(
              message: _maintenanceLoadError!,
              onRetry: _loadMaintenanceRecords,
            );
          }
          return ReportsPage(
            items: _items,
            movements: _movements,
            maintenanceRecords: _maintenanceRecords,
            searchQuery: searchQuery,
            canExport: _permissions.canExportReports,
          );
        },
      ),
      'Pengguna' => ValueListenableBuilder<String>(
        valueListenable: _searchQuery,
        builder: (context, searchQuery, _) {
          if (_isLoadingUsers) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_userLoadError != null) {
            return _LoadErrorPanel(
              message: _userLoadError!,
              onRetry: _loadUsers,
            );
          }
          return UsersPage(
            users: _users,
            searchQuery: searchQuery,
            onCreate: _createUser,
            onEdit: _editUser,
            onToggleActive: _toggleUserActive,
          );
        },
      ),
      'Lokasi' => ValueListenableBuilder<String>(
        valueListenable: _searchQuery,
        builder: (context, searchQuery, _) {
          if (_isLoadingLocations) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_locationLoadError != null) {
            return _LoadErrorPanel(
              message: _locationLoadError!,
              onRetry: _loadLocations,
            );
          }
          return LocationsPage(
            locations: _locations,
            searchQuery: searchQuery,
            onSave: _saveLocation,
            onToggleActive: _toggleLocationActive,
            canEdit: _permissions.canManageMasterData,
          );
        },
      ),
      'Jenis & Kategori' => ValueListenableBuilder<String>(
        valueListenable: _searchQuery,
        builder: (context, searchQuery, _) {
          if (_isLoadingCatalogs) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_catalogLoadError != null) {
            return _LoadErrorPanel(
              message: _catalogLoadError!,
              onRetry: _loadCatalogs,
            );
          }
          return ItemKindsCategoriesPage(
            itemKinds: _itemKinds,
            categories: _itemCategories,
            searchQuery: searchQuery,
            onSaveKind: _saveItemKind,
            onToggleKind: _toggleItemKind,
            onSaveCategory: _saveItemCategory,
            onToggleCategory: _toggleItemCategory,
            canEdit: _permissions.canManageMasterData,
          );
        },
      ),
      _ => _PageNotReady(page: _selectedPage),
    };
  }

  Widget _buildDashboardPage({required bool isDesktop}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageHeading(
          userName: widget.currentUser.name,
          onAddItem: _showAddItemDialog,
          canManageAssets: _permissions.canManageAssets,
          canExportReports: _permissions.canExportReports,
        ),
        const SizedBox(height: 24),
        _SummaryGrid(items: _items),
        const SizedBox(height: 22),
        _OverviewSection(isDesktop: isDesktop, items: _items),
        const SizedBox(height: 22),
        ValueListenableBuilder<String>(
          valueListenable: _searchQuery,
          builder: (context, searchQuery, _) {
            if (_isLoadingAssets) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_assetLoadError != null) {
              return _LoadErrorPanel(
                message: _assetLoadError!,
                onRetry: _loadAssets,
              );
            }
            return _InventoryTable(
              items: _filterItems(searchQuery),
              conditionFilter: _conditionFilter,
              onConditionChanged: (value) {
                setState(() => _conditionFilter = value);
              },
              onViewAll: () => _selectPage('Inventaris'),
            );
          },
        ),
      ],
    );
  }
}

// CATATAN PEMELIHARAAN: banner hanya menyebut modul yang masih berupa contoh;
// hapus atau revisi saat grafik tren dan ekspor laporan punya layanan nyata.
class _UnconnectedModulesBanner extends StatelessWidget {
  const _UnconnectedModulesBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: const Color(0xFFFFF3DF),
      child: const Text(
        'Catatan: inventaris, data master, mutasi, dan pemeliharaan terhubung ke server. Grafik tren serta ekspor laporan masih contoh.',
        style: TextStyle(color: Color(0xFF79551A), fontSize: 12),
      ),
    );
  }
}

/// Placeholder untuk menu yang sudah tampil di navbar tetapi belum punya fitur.
/// Ganti pemetaan di [_InventoryDashboardState._buildSelectedPage] saat dibuat.
class _PageNotReady extends StatelessWidget {
  const _PageNotReady({required this.page});

  final String page;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDF0F4)),
      ),
      child: Text(
        'Halaman $page akan dirancang pada tahap berikutnya.',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _LoadErrorPanel extends StatelessWidget {
  const _LoadErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 36,
            color: Colors.blueGrey,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba lagi'),
          ),
        ],
      ),
    );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({
    required this.userName,
    required this.onAddItem,
    required this.canManageAssets,
    required this.canExportReports,
  });

  final String userName;
  final VoidCallback onAddItem;
  final bool canManageAssets;
  final bool canExportReports;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 650;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selamat pagi, ${userName.split(' ').first} 👋',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontSize: compact ? 21 : 24),
            ),
            const SizedBox(height: 6),
            const Text(
              'Berikut ringkasan kondisi sarana dan prasarana sekolah.',
            ),
          ],
        );
        final actions = Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            if (canExportReports)
              OutlinedButton.icon(
                onPressed: () {
                  // CATATAN MOCKUP: tombol hanya memberi notifikasi, belum
                  // menghasilkan file; sambungkan ke service ekspor laporan.
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Ekspor laporan tersedia pada tahap berikutnya.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Ekspor'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF44536B),
                  side: const BorderSide(color: Color(0xFFDDE3EC)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                ),
              ),
            if (canManageAssets)
              FilledButton.icon(
                onPressed: onAddItem,
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('Tambah Barang'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF168B83),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 16), actions],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            actions,
          ],
        );
      },
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.items});

  final List<InventoryItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1050
            ? 4
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        const spacing = 14.0;
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        final total = items.length;
        final good = items.where((item) => item.condition == 'Bagus').length;
        final needsAttention = total - good;
        final damaged = items.where((item) => item.condition == 'Rusak').length;
        final cards = [
          _MetricCard(
            label: 'Total Aset',
            value: total.toString(),
            detail: 'Unit aset aktif dari server',
            icon: Icons.inventory_2_outlined,
            tint: const Color(0xFFE7F4F2),
            iconColor: const Color(0xFF168B83),
          ),
          _MetricCard(
            label: 'Kondisi Bagus',
            value: good.toString(),
            detail: 'Unit dalam kondisi baik',
            icon: Icons.check_circle_outline_rounded,
            tint: const Color(0xFFE7F4F2),
            iconColor: const Color(0xFF168B83),
          ),
          _MetricCard(
            label: 'Perlu Perhatian',
            value: needsAttention.toString(),
            detail: 'Perbaikan, service, atau rusak',
            icon: Icons.build_circle_outlined,
            tint: const Color(0xFFFFF2E3),
            iconColor: const Color(0xFFE59B3F),
          ),
          _MetricCard(
            label: 'Aset Rusak',
            value: damaged.toString(),
            detail: 'Unit dengan kondisi rusak',
            icon: Icons.warning_amber_rounded,
            tint: const Color(0xFFFFEDE8),
            iconColor: const Color(0xFFE47767),
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map((card) => SizedBox(width: cardWidth, child: card))
              .toList(),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.tint,
    required this.iconColor,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color tint;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDF0F4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080D2340),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF172B4D),
              fontSize: 25,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({required this.isDesktop, required this.items});

  final bool isDesktop;
  final List<InventoryItem> items;

  @override
  Widget build(BuildContext context) {
    final chart = _Panel(
      title: 'Tren Aset (pratinjau)',
      subtitle: 'Grafik contoh; tanggal perolehan belum tersedia dari API',
      trailing: _SmallDropdown(
        value: 'Tahun ini',
        items: const ['Tahun ini', '6 bulan terakhir'],
        onChanged: (_) {},
      ),
      child: const _InventoryChart(),
    );
    final status = _Panel(
      title: 'Kondisi Barang',
      subtitle: 'Status kondisi seluruh aset',
      trailing: IconButton(
        onPressed: () {},
        tooltip: 'Opsi kondisi',
        icon: const Icon(Icons.more_horiz_rounded),
        color: const Color(0xFF8994A7),
      ),
      child: _ConditionOverview(items: items),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 860) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: chart),
              const SizedBox(width: 16),
              Expanded(flex: 4, child: status),
            ],
          );
        }
        return Column(children: [chart, const SizedBox(height: 16), status]);
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDF0F4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080D2340),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _SmallDropdown extends StatelessWidget {
  const _SmallDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isDense: true,
        borderRadius: BorderRadius.circular(12),
        style: const TextStyle(
          color: Color(0xFF53627A),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        items: items
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

// CATATAN MOCKUP: bars are illustrative because assets have no acquisition
// date yet; replace them only when the API supplies validated trend data.
class _InventoryChart extends StatelessWidget {
  const _InventoryChart();

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun'];
  static const _assetValues = <double>[50, 65, 58, 76, 69, 92];
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Row(
          children: [
            _ChartLegend(color: Color(0xFF168B83), label: 'Contoh aset'),
            Spacer(),
            Text(
              'Unit',
              style: TextStyle(color: Color(0xFF8994A7), fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 145,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(_months.length, (index) {
              return Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _Bar(
                            height: _assetValues[index],
                            color: const Color(0xFF168B83),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _months[index],
                      style: const TextStyle(
                        color: Color(0xFF8994A7),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF69778D), fontSize: 10),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
      ),
    );
  }
}

class _ConditionOverview extends StatelessWidget {
  const _ConditionOverview({required this.items});

  final List<InventoryItem> items;

  @override
  Widget build(BuildContext context) {
    final total = items.length;
    final conditions = [
      _ConditionData(
        'Bagus',
        items.where((item) => item.condition == 'Bagus').length,
        _conditionFraction('Bagus', total),
        const Color(0xFF42A786),
      ),
      _ConditionData(
        'Perlu perbaikan',
        items.where((item) => item.condition == 'Perlu perbaikan').length,
        _conditionFraction('Perlu perbaikan', total),
        const Color(0xFFE6A444),
      ),
      _ConditionData(
        'Dalam service',
        items.where((item) => item.condition == 'Dalam service').length,
        _conditionFraction('Dalam service', total),
        const Color(0xFF6685D2),
      ),
      _ConditionData(
        'Rusak',
        items.where((item) => item.condition == 'Rusak').length,
        _conditionFraction('Rusak', total),
        const Color(0xFFE47767),
      ),
    ];
    return Column(
      children: conditions
          .map(
            (condition) => Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: condition.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          condition.label,
                          style: const TextStyle(
                            color: Color(0xFF53627A),
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Text(
                        condition.count.toString(),
                        style: const TextStyle(
                          color: Color(0xFF172B4D),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 33,
                        child: Text(
                          '${(condition.fraction * 100).round()}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Color(0xFF8994A7),
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: condition.fraction,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFF0F2F5),
                      valueColor: AlwaysStoppedAnimation(condition.color),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  double _conditionFraction(String condition, int total) {
    if (total == 0) return 0;
    return items.where((item) => item.condition == condition).length / total;
  }
}

class _ConditionData {
  const _ConditionData(this.label, this.count, this.fraction, this.color);

  final String label;
  final int count;
  final double fraction;
  final Color color;
}

class _InventoryTable extends StatelessWidget {
  const _InventoryTable({
    required this.items,
    required this.conditionFilter,
    required this.onConditionChanged,
    required this.onViewAll,
  });

  final List<InventoryItem> items;
  final String conditionFilter;
  final ValueChanged<String> onConditionChanged;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDF0F4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080D2340),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 650;
              final title = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Barang Terbaru',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Daftar barang yang baru ditambahkan atau diperbarui',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              );
              final controls = Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ConditionFilter(
                    value: conditionFilter,
                    onChanged: onConditionChanged,
                  ),
                  OutlinedButton.icon(
                    onPressed: onViewAll,
                    icon: const Icon(Icons.list_alt_rounded, size: 17),
                    label: const Text('Lihat semua'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF44536B),
                      side: const BorderSide(color: Color(0xFFDDE3EC)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 14), controls],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  controls,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 650) {
                if (items.isEmpty) return const _EmptyItems();
                return Column(
                  children: items
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _CompactInventoryRow(item: item),
                        ),
                      )
                      .toList(),
                );
              }
              if (items.isEmpty) return const _EmptyItems();
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth,
                      minHeight: 180,
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
                      horizontalMargin: 14,
                      columnSpacing: 24,
                      columns: const [
                        DataColumn(label: Text('NAMA BARANG')),
                        DataColumn(label: Text('KATEGORI')),
                        DataColumn(label: Text('LOKASI')),
                        DataColumn(label: Text('KONDISI')),
                      ],
                      rows: items
                          .map(
                            (item) => DataRow(
                              cells: [
                                DataCell(_ItemIdentity(item: item)),
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
                                DataCell(
                                  _ConditionBadge(condition: item.condition),
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
        ],
      ),
    );
  }
}

class _ConditionFilter extends StatelessWidget {
  const _ConditionFilter({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const _options = [
    'Semua kondisi',
    'Bagus',
    'Perlu perbaikan',
    'Dalam service',
    'Rusak',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 11),
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
          items: _options
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

class _ItemIdentity extends StatelessWidget {
  const _ItemIdentity({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: item.color,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(item.icon, color: const Color(0xFF54657C), size: 18),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.name,
              style: const TextStyle(
                color: Color(0xFF263752),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.code,
              style: const TextStyle(color: Color(0xFF8994A7), fontSize: 9),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConditionBadge extends StatelessWidget {
  const _ConditionBadge({required this.condition});

  final String condition;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, dot) = switch (condition) {
      'Bagus' => (
        const Color(0xFFE9F6F0),
        const Color(0xFF368A6C),
        const Color(0xFF43A786),
      ),
      'Perlu perbaikan' => (
        const Color(0xFFFFF4E4),
        const Color(0xFFB77B27),
        const Color(0xFFE6A444),
      ),
      'Dalam service' => (
        const Color(0xFFEDF1FF),
        const Color(0xFF5C73B3),
        const Color(0xFF6685D2),
      ),
      _ => (
        const Color(0xFFFFEEEB),
        const Color(0xFFB45F52),
        const Color(0xFFE47767),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            condition,
            style: TextStyle(
              color: foreground,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactInventoryRow extends StatelessWidget {
  const _CompactInventoryRow({required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
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
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: item.color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  item.icon,
                  color: const Color(0xFF54657C),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF263752),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8994A7),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Align(
            alignment: Alignment.centerRight,
            child: _ConditionBadge(condition: item.condition),
          ),
        ],
      ),
    );
  }
}

class _EmptyItems extends StatelessWidget {
  const _EmptyItems();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, color: Color(0xFFADB7C5), size: 28),
          SizedBox(height: 8),
          Text(
            'Barang tidak ditemukan',
            style: TextStyle(
              color: Color(0xFF69778D),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Coba ubah kata pencarian atau filter.',
            style: TextStyle(color: Color(0xFF8994A7), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Form satu aset yang mengembalikan draft untuk dikirim ke API oleh parent.
///
/// CATATAN PEMELIHARAAN: dialog hanya mengembalikan nama, ID kategori/lokasi,
/// dan kondisi awal; backend mengambil jenis aset tetap, memvalidasi referensi,
/// lalu membuat kode unit. Jika katalog kondisi berubah, sesuaikan pilihannya
/// di sini dan mapping code pada handler inventaris.
class AddInventoryDialog extends StatefulWidget {
  const AddInventoryDialog({
    super.key,
    required this.locations,
    required this.categories,
    required this.itemKinds,
    this.initialItem,
  });

  final List<MasterLocation> locations;
  final List<ItemCategory> categories;
  final List<ItemKind> itemKinds;
  final InventoryItem? initialItem;

  @override
  State<AddInventoryDialog> createState() => _AddInventoryDialogState();
}

class _AddInventoryDialogState extends State<AddInventoryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String? _selectedCategoryId;
  String? _selectedKindId;
  String _condition = 'Bagus';
  String? _selectedLocationId;

  List<MasterLocation> get _activeLocations =>
      widget.locations.where((location) => location.isActive).toList();
  List<ItemCategory> get _activeCategories =>
      widget.categories.where((category) => category.isActive).toList();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.initialItem;
    if (existing != null) {
      _nameController.text = existing.name;
      _selectedCategoryId =
          _activeCategories.any((value) => value.id == existing.categoryId)
          ? existing.categoryId
          : (_activeCategories.isEmpty ? null : _activeCategories.first.id);
      _selectedLocationId =
          _activeLocations.any((value) => value.id == existing.locationId)
          ? existing.locationId
          : (_activeLocations.isEmpty ? null : _activeLocations.first.id);
      _condition = existing.condition;
      _selectedKindId =
          widget.itemKinds.any((value) => value.id == existing.kindId)
          ? existing.kindId
          : (widget.itemKinds.isEmpty ? null : widget.itemKinds.first.id);
      return;
    }
    final activeLocations = _activeLocations;
    final defaultLocations = activeLocations
        .where((location) => location.code == 'RNG-001')
        .toList();
    if (activeLocations.isNotEmpty) {
      _selectedLocationId = defaultLocations.isNotEmpty
          ? defaultLocations.first.id
          : activeLocations.first.id;
    }
    final activeCategories = _activeCategories;
    final defaultCategories = activeCategories
        .where((category) => category.code.toLowerCase() == 'elektronik')
        .toList();
    if (activeCategories.isNotEmpty) {
      _selectedCategoryId = defaultCategories.isNotEmpty
          ? defaultCategories.first.id
          : activeCategories.first.id;
    }
    if (widget.itemKinds.isNotEmpty) {
      _selectedKindId = widget.itemKinds.first.id;
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final locationId = _selectedLocationId;
    final categoryId = _selectedCategoryId;
    final kindId = _selectedKindId;
    if (locationId == null || categoryId == null || kindId == null) return;
    final location = widget.locations.firstWhere(
      (candidate) => candidate.id == locationId,
    );
    final category = widget.categories.firstWhere(
      (candidate) => candidate.id == categoryId,
    );
    Navigator.of(context).pop(
      InventoryItem(
        code: widget.initialItem?.code ?? '',
        assetId: widget.initialItem?.assetId,
        itemId: widget.initialItem?.itemId,
        kindId: kindId,
        categoryId: category.id,
        name: _nameController.text.trim(),
        category: category.name,
        locationId: location.id,
        location: location.name,
        condition: _condition,
        icon: category.name.toLowerCase().contains('elektronik')
            ? Icons.devices_other_rounded
            : category.name.toLowerCase().contains('mebel')
            ? Icons.chair_alt_rounded
            : Icons.inventory_2_outlined,
        color: const Color(0xFFE9F2FF),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initialItem == null ? 'Tambah Barang' : 'Edit Data Aset',
        style: TextStyle(color: Color(0xFF172B4D), fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 430,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.initialItem == null
                      ? 'Satu unit aset dibuat untuk setiap barcode. Pilih kategori dan lokasi aktif.'
                      : 'Perubahan berlaku untuk unit ${widget.initialItem!.code} ini. Unit lain dengan nama sama tidak ikut berubah.',
                  style: TextStyle(color: Color(0xFF69778D), fontSize: 12),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Nama barang',
                    hintText: 'Contoh: Laptop ruang guru',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Nama barang wajib diisi'
                      : null,
                ),
                DropdownButtonFormField<String>(
                  key: const Key('inventory-kind-input'),
                  isExpanded: true,
                  initialValue: _selectedKindId,
                  decoration: const InputDecoration(labelText: 'Jenis barang'),
                  items: widget.itemKinds
                      .map(
                        (kind) => DropdownMenuItem(
                          value: kind.id,
                          child: Text(kind.name),
                        ),
                      )
                      .toList(),
                  validator: (value) =>
                      value == null ? 'Pilih jenis barang' : null,
                  onChanged: (value) {
                    if (value != null) setState(() => _selectedKindId = value);
                  },
                ),
                const SizedBox(height: 14),
                const Text(
                  'Kode inventaris dibuat dari kode sekolah, kategori, tahun, dan nomor urut.',
                  style: TextStyle(color: Color(0xFF69778D), fontSize: 11),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  key: const Key('inventory-category-input'),
                  isExpanded: true,
                  initialValue: _selectedCategoryId,
                  decoration: const InputDecoration(labelText: 'Kategori'),
                  items: _activeCategories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.id,
                          child: Text(category.name),
                        ),
                      )
                      .toList(),
                  validator: (value) =>
                      value == null ? 'Pilih kategori barang' : null,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedCategoryId = value);
                    }
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _condition,
                  decoration: const InputDecoration(labelText: 'Kondisi'),
                  items:
                      const [
                            'Bagus',
                            'Perlu perbaikan',
                            'Dalam service',
                            'Rusak',
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _condition = value);
                  },
                ),
                const SizedBox(height: 14),
                if (_activeLocations.isEmpty)
                  const _NoActiveLocationsNotice()
                else
                  DropdownButtonFormField<String>(
                    key: const Key('inventory-location-input'),
                    isExpanded: true,
                    initialValue: _selectedLocationId,
                    decoration: const InputDecoration(
                      labelText: 'Lokasi barang',
                    ),
                    items: _activeLocations
                        .map(
                          (location) => DropdownMenuItem(
                            value: location.id,
                            child: Text(
                              location.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    validator: (value) =>
                        value == null ? 'Pilih lokasi barang' : null,
                    onChanged: (value) {
                      setState(() => _selectedLocationId = value);
                    },
                  ),
                if (_activeCategories.isEmpty)
                  const _NoActiveCategoriesNotice(),
                const SizedBox(height: 8),
                const Text(
                  'Pilihan mengikuti lokasi aktif pada menu Lokasi.',
                  style: TextStyle(color: Color(0xFF69778D), fontSize: 11),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F7F6),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.qr_code_2_rounded,
                        color: Color(0xFF168B83),
                        size: 20,
                      ),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Kode aset dan barcode resmi dibuat oleh server setelah penyimpanan berhasil.',
                          style: TextStyle(
                            color: Color(0xFF4F6D6A),
                            fontSize: 11,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
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
          onPressed:
              _activeLocations.isEmpty ||
                  _activeCategories.isEmpty ||
                  widget.itemKinds.isEmpty
              ? null
              : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF168B83),
          ),
          child: Text(
            widget.initialItem == null ? 'Simpan aset' : 'Simpan perubahan',
          ),
        ),
      ],
    );
  }
}

class _NoActiveCategoriesNotice extends StatelessWidget {
  const _NoActiveCategoriesNotice();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'Belum ada kategori aktif. Tambahkan atau aktifkan kategori terlebih dahulu.',
        style: TextStyle(color: Color(0xFFB77B27), fontSize: 12, height: 1.4),
      ),
    );
  }
}

class _NoActiveLocationsNotice extends StatelessWidget {
  const _NoActiveLocationsNotice();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'Belum ada lokasi aktif. Tambahkan atau aktifkan lokasi melalui menu Lokasi terlebih dahulu.',
        style: TextStyle(color: Color(0xFFB77B27), fontSize: 12, height: 1.4),
      ),
    );
  }
}
