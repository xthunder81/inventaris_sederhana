/// Data akun yang dibutuhkan UI Pengguna; bukan tempat menyimpan password.
///
/// CATATAN PEMELIHARAAN: ketika atribut akun ditambah/diubah, perbarui
/// constructor, [copyWith], data demo, dan pemetaan repository/API bersama-sama.
class UserAccount {
  const UserAccount({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    required this.isActive,
    this.lastLoginAt,
  });

  final String id;
  final String name;
  final String username;
  final String role;
  final bool isActive;
  final DateTime? lastLoginAt;

  /// Membuat salinan akun untuk edit status/profil tanpa mengganti ID.
  ///
  /// Tambahkan field baru di sini jika field itu dapat berubah saat edit.
  UserAccount copyWith({
    String? name,
    String? username,
    String? role,
    bool? isActive,
    DateTime? lastLoginAt,
  }) {
    return UserAccount(
      id: id,
      name: name ?? this.name,
      username: username ?? this.username,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }
}

// CATATAN MOCKUP: daftar awal untuk pratinjau halaman Pengguna. Ganti sumber
// ini dengan repository/API; autentikasi dan kata sandi tidak disimpan di sini.
final demoUsers = <UserAccount>[
  UserAccount(
    id: 'user-001',
    name: 'Admin Sekolah',
    username: 'admin',
    role: 'Admin',
    isActive: true,
    lastLoginAt: DateTime(2026, 11, 12, 8, 15),
  ),
  UserAccount(
    id: 'user-002',
    name: 'Budi Santoso',
    username: 'budi.petugas',
    role: 'Petugas',
    isActive: true,
    lastLoginAt: DateTime(2026, 11, 12, 7, 42),
  ),
  UserAccount(
    id: 'user-003',
    name: 'Siti Rahmawati',
    username: 'siti.petugas',
    role: 'Petugas',
    isActive: true,
    lastLoginAt: DateTime(2026, 11, 11, 15, 20),
  ),
  UserAccount(
    id: 'user-004',
    name: 'Ahmad Fauzi',
    username: 'ahmad.pimpinan',
    role: 'Pimpinan',
    isActive: true,
    lastLoginAt: DateTime(2026, 11, 10, 9, 5),
  ),
  UserAccount(
    id: 'user-005',
    name: 'Rina Handayani',
    username: 'rina.petugas',
    role: 'Petugas',
    isActive: false,
  ),
];
