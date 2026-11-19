import 'package:flutter/material.dart';

/// Header reusable untuk halaman dashboard dan fitur lain.
///
/// Pencarian, buka drawer, dan notifikasi diserahkan ke halaman pemakai lewat
/// callback agar widget ini tidak bergantung pada state atau data tertentu.
/// CATATAN PEMELIHARAAN: controller dimiliki/dibuang oleh pemanggil; callback
/// mengirim perubahan pencarian dan aksi profil kembali ke halaman pemilik.
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.isDesktop,
    required this.searchController,
    required this.onSearchChanged,
    required this.onMenuPressed,
    required this.onChangePassword,
    required this.onLogout,
    this.searchHint = 'Cari barang, kode, atau lokasi...',
    this.onNotificationsPressed,
    this.userName = 'Admin Sekolah',
    this.userRole = 'Administrator',
  });

  final bool isDesktop;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback? onMenuPressed;
  // CATATAN: pemanggil membuka alur ganti password dan mengakhiri sesi;
  // widget header hanya memicu callback, tidak mengelola autentikasi sendiri.
  final VoidCallback onChangePassword;
  final Future<void> Function() onLogout;
  final String searchHint;
  final VoidCallback? onNotificationsPressed;
  final String userName;
  final String userRole;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 32 : 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEBEEF3))),
      ),
      child: Row(
        children: [
          if (!isDesktop) ...[
            IconButton(
              onPressed: onMenuPressed,
              icon: const Icon(Icons.menu_rounded),
              tooltip: 'Buka menu',
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Align(
              alignment: isDesktop ? Alignment.centerLeft : Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    key: const Key('inventory-search'),
                    controller: searchController,
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      hintText: searchHint,
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                      contentPadding: EdgeInsets.symmetric(vertical: 9),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed:
                onNotificationsPressed ??
                () {
                  // CATATAN MOCKUP: jalur default hanya menampilkan pesan.
                  // Pemanggil harus memberi callback notifikasi saat API siap.
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('Belum ada notifikasi baru.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                },
            tooltip: 'Notifikasi',
            icon: Badge(
              smallSize: 8,
              backgroundColor: const Color(0xFFEF7D62),
              child: Icon(
                Icons.notifications_none_rounded,
                color: Colors.blueGrey.shade700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 30, color: const Color(0xFFE9EDF2)),
          const SizedBox(width: 16),
          PopupMenuButton<_ProfileAction>(
            tooltip: 'Menu profil',
            position: PopupMenuPosition.under,
            offset: const Offset(0, 8),
            onSelected: (action) async {
              switch (action) {
                case _ProfileAction.changePassword:
                  onChangePassword();
                case _ProfileAction.logout:
                  await onLogout();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _ProfileAction.changePassword,
                child: Row(
                  children: [
                    Icon(Icons.lock_reset_rounded, size: 19),
                    SizedBox(width: 10),
                    Text('Ubah kata sandi'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _ProfileAction.logout,
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 19),
                    SizedBox(width: 10),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: Color(0xFFDDF2EE),
                    child: Text(
                      'AD',
                      style: TextStyle(
                        color: Color(0xFF168B83),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (isDesktop) ...[
                    const SizedBox(width: 10),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF263752),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          userRole,
                          style: const TextStyle(
                            color: Color(0xFF8994A7),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.blueGrey.shade400,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ProfileAction { changePassword, logout }
