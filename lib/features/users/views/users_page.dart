// CATATAN PEMELIHARAAN: file ini mengatur filter, daftar, dan aksi akun.
// _filteredUsers menentukan akun yang cocok; _pageSize menentukan jumlah
// per halaman. Jika salah satunya berubah, sesuaikan tes widget terkait.
// Aksi data diteruskan ke callback; reset password masih pratinjau. Backend
// harus menyimpan hash dan mewajibkan penggantian password saat login.
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/user_account.dart';

/// Hasil dialog akun; kata sandi hanya hidup pada alur create dan tidak masuk
/// ke model UserAccount yang dapat dipakai untuk tabel/profil.
class UserAccountDraft {
  const UserAccountDraft({required this.user, this.initialPassword = ''});

  final UserAccount user;
  final String initialPassword;
}

class UsersPage extends StatefulWidget {
  const UsersPage({
    super.key,
    required this.users,
    required this.searchQuery,
    required this.onCreate,
    required this.onEdit,
    required this.onToggleActive,
  });

  final List<UserAccount> users;
  final String searchQuery;
  final VoidCallback onCreate;
  final ValueChanged<UserAccount> onEdit;
  final ValueChanged<UserAccount> onToggleActive;

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  // CATATAN: ubah angka ini untuk mengatur banyaknya akun dalam satu halaman.
  static const _pageSize = 8;

  String _roleFilter = 'Semua peran';
  String _statusFilter = 'Semua status';
  int _currentPage = 0;

  // CATATAN: pencarian, peran, dan status diterapkan sebelum pagination agar
  // jumlah hasil dan isi setiap halaman selalu sesuai filter yang aktif.
  List<UserAccount> get _filteredUsers {
    final query = widget.searchQuery.trim().toLowerCase();
    return widget.users.where((user) {
      final matchesQuery =
          query.isEmpty ||
          user.name.toLowerCase().contains(query) ||
          user.username.toLowerCase().contains(query) ||
          user.role.toLowerCase().contains(query);
      final matchesRole =
          _roleFilter == 'Semua peran' || user.role == _roleFilter;
      final matchesStatus = switch (_statusFilter) {
        'Aktif' => user.isActive,
        'Nonaktif' => !user.isActive,
        _ => true,
      };
      return matchesQuery && matchesRole && matchesStatus;
    }).toList();
  }

  @override
  void didUpdateWidget(covariant UsersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // CATATAN: kembali ke awal saat pencarian berubah, lalu jepit indeks
    // halaman bila filter/data baru mengurangi jumlah halaman.
    if (oldWidget.searchQuery != widget.searchQuery) {
      _currentPage = 0;
    }

    final pageCount = (_filteredUsers.length + _pageSize - 1) ~/ _pageSize;
    if (pageCount == 0) {
      _currentPage = 0;
    } else if (_currentPage >= pageCount) {
      _currentPage = pageCount - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredUsers = _filteredUsers;
    final pageCount = (filteredUsers.length + _pageSize - 1) ~/ _pageSize;
    final firstIndex = _currentPage * _pageSize;
    // CATATAN: tabel desktop dan kartu mobile memakai potongan data yang sama.
    final visibleUsers = filteredUsers
        .skip(firstIndex)
        .take(_pageSize)
        .toList();
    final activeCount = widget.users.where((user) => user.isActive).length;
    final inactiveCount = widget.users.length - activeCount;

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
                  'Pengguna',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                const Text('Kelola akun dan hak akses aplikasi sekolah.'),
              ],
            );
            final addButton = FilledButton.icon(
              key: const Key('create-user'),
              onPressed: widget.onCreate,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('Tambah Pengguna'),
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
                children: [heading, const SizedBox(height: 16), addButton],
              );
            }
            return Row(
              children: [
                Expanded(child: heading),
                addButton,
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 740
                ? 3
                : constraints.maxWidth >= 440
                ? 2
                : 1;
            const spacing = 12.0;
            final cardWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            final cards = [
              _UserMetric(
                label: 'Total pengguna',
                value: widget.users.length.toString(),
                icon: Icons.people_outline_rounded,
                tint: const Color(0xFFEAF0FF),
                iconColor: const Color(0xFF5677C8),
              ),
              _UserMetric(
                label: 'Akun aktif',
                value: activeCount.toString(),
                icon: Icons.verified_user_outlined,
                tint: const Color(0xFFE7F4F2),
                iconColor: const Color(0xFF168B83),
              ),
              _UserMetric(
                label: 'Akun nonaktif',
                value: inactiveCount.toString(),
                icon: Icons.person_off_outlined,
                tint: const Color(0xFFFFF2E3),
                iconColor: const Color(0xFFE59B3F),
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
        ),
        const SizedBox(height: 20),
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 650;
                  final title = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daftar Pengguna',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${filteredUsers.length} akun ditampilkan',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  );
                  final filters = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FilterDropdown(
                        key: const Key('user-role-filter'),
                        value: _roleFilter,
                        options: const [
                          'Semua peran',
                          'Admin',
                          'Petugas',
                          'Pimpinan',
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            // Filter baru selalu mulai dari halaman pertama.
                            setState(() {
                              _roleFilter = value;
                              _currentPage = 0;
                            });
                          }
                        },
                      ),
                      _FilterDropdown(
                        key: const Key('user-status-filter'),
                        value: _statusFilter,
                        options: const ['Semua status', 'Aktif', 'Nonaktif'],
                        onChanged: (value) {
                          if (value != null) {
                            // Filter baru selalu mulai dari halaman pertama.
                            setState(() {
                              _statusFilter = value;
                              _currentPage = 0;
                            });
                          }
                        },
                      ),
                    ],
                  );
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const SizedBox(height: 14), filters],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: title),
                      filters,
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (filteredUsers.isEmpty) return const _EmptyUsers();
                  if (constraints.maxWidth < 740) {
                    return Column(
                      children: visibleUsers
                          .map(
                            (user) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _UserCard(
                                user: user,
                                onEdit: () => widget.onEdit(user),
                                onToggleActive: () =>
                                    widget.onToggleActive(user),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  }
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
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
                          columns: const [
                            DataColumn(label: Text('PENGGUNA')),
                            DataColumn(label: Text('PERAN')),
                            DataColumn(label: Text('LOGIN TERAKHIR')),
                            DataColumn(label: Text('STATUS')),
                            DataColumn(label: Text('AKSI')),
                          ],
                          rows: visibleUsers
                              .map(
                                (user) => DataRow(
                                  cells: [
                                    DataCell(_UserIdentity(user: user)),
                                    DataCell(_RoleBadge(role: user.role)),
                                    DataCell(
                                      Text(_formatLogin(user.lastLoginAt)),
                                    ),
                                    DataCell(
                                      _UserStatusBadge(isActive: user.isActive),
                                    ),
                                    DataCell(
                                      _UserActions(
                                        user: user,
                                        onEdit: () => widget.onEdit(user),
                                        onToggleActive: () =>
                                            widget.onToggleActive(user),
                                      ),
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
              if (filteredUsers.length > _pageSize) ...[
                const SizedBox(height: 12),
                _UserPagination(
                  currentPage: _currentPage,
                  pageCount: pageCount,
                  firstIndex: firstIndex + 1,
                  lastIndex: firstIndex + visibleUsers.length,
                  totalUsers: filteredUsers.length,
                  onPrevious: () => setState(() => _currentPage--),
                  onNext: () => setState(() => _currentPage++),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _UserMetric extends StatelessWidget {
  const _UserMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
    required this.iconColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEDF0F4)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF172B4D),
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

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
        child: DropdownButton<String>(
          value: value,
          borderRadius: BorderRadius.circular(12),
          style: const TextStyle(color: Color(0xFF53627A), fontSize: 11),
          items: options
              .map(
                (option) =>
                    DropdownMenuItem(value: option, child: Text(option)),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _UserIdentity extends StatelessWidget {
  const _UserIdentity({required this.user});

  final UserAccount user;

  @override
  Widget build(BuildContext context) {
    final initials = user.name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFFE7F4F2),
          child: Text(
            initials,
            style: const TextStyle(
              color: Color(0xFF168B83),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user.name,
              style: const TextStyle(
                color: Color(0xFF263752),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '@${user.username}',
              style: const TextStyle(color: Color(0xFF8994A7), fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final color = switch (role) {
      'Admin' => const Color(0xFF6D5DB3),
      'Pimpinan' => const Color(0xFF5376C6),
      _ => const Color(0xFF168B83),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        role,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _UserStatusBadge extends StatelessWidget {
  const _UserStatusBadge({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? const Color(0xFF368A6C) : const Color(0xFF8994A7);
    final background = isActive
        ? const Color(0xFFE9F6F0)
        : const Color(0xFFF0F2F5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isActive ? 'Aktif' : 'Nonaktif',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Menu aksi akun; perubahan akun diproses parent melalui callback.
/// Reset password di sini hanya membuka dialog pratinjau lokal.
class _UserActions extends StatelessWidget {
  const _UserActions({
    required this.user,
    required this.onEdit,
    required this.onToggleActive,
  });

  final UserAccount user;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Aksi ${user.name}',
      onSelected: (action) {
        if (action == 'edit') onEdit();
        if (action == 'toggle') onToggleActive();
        if (action == 'reset') {
          showDialog<void>(
            context: context,
            builder: (context) => _ResetUserPasswordDialog(user: user),
          );
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.edit_outlined, size: 18),
            title: Text('Ubah pengguna'),
          ),
        ),
        const PopupMenuItem(
          value: 'reset',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.lock_reset_rounded, size: 18),
            title: Text('Reset password'),
          ),
        ),
        PopupMenuItem(
          value: 'toggle',
          child: ListTile(
            dense: true,
            leading: Icon(
              user.isActive ? Icons.person_off_outlined : Icons.person_outline,
              size: 18,
            ),
            title: Text(
              user.isActive ? 'Nonaktifkan (arsip)' : 'Aktifkan kembali',
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

class _ResetUserPasswordDialog extends StatefulWidget {
  const _ResetUserPasswordDialog({required this.user});

  final UserAccount user;

  @override
  State<_ResetUserPasswordDialog> createState() =>
      _ResetUserPasswordDialogState();
}

class _ResetUserPasswordDialogState extends State<_ResetUserPasswordDialog> {
  String? _previewPassword;

  // CATATAN MOCKUP: password acak hanya untuk memperagakan tampilan.
  // Jangan gunakan sebagai reset sungguhan; backend harus membuat dan
  // menerapkan kredensial sementara serta flag wajib ganti saat login.
  void _generatePreviewPassword() {
    const characters =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%';
    final random = Random.secure();
    setState(() {
      _previewPassword = List.generate(
        16,
        (_) => characters[random.nextInt(characters.length)],
      ).join();
    });
  }

  @override
  Widget build(BuildContext context) {
    final generated = _previewPassword != null;
    return AlertDialog(
      title: Text(
        'Reset password — ${widget.user.name}',
        style: const TextStyle(
          color: Color(0xFF172B4D),
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Username: ${widget.user.username}'),
            const SizedBox(height: 12),
            if (!generated)
              const Text(
                'Buat password sementara sekali pakai. Pada sistem nyata, '
                'pengguna wajib menggantinya saat login berikutnya.',
                style: TextStyle(height: 1.45),
              )
            else ...[
              const Text(
                'Password sementara (hanya ditampilkan pada pratinjau ini):',
                style: TextStyle(height: 1.45),
              ),
              const SizedBox(height: 8),
              SelectableText(
                _previewPassword!,
                key: const Key('temporary-user-password'),
                style: const TextStyle(
                  color: Color(0xFF172B4D),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
            const SizedBox(height: 14),
            const Text(
              'Catatan mockup: password ini tidak mengubah akun atau dapat '
              'digunakan untuk login. Hubungkan ke backend agar password '
              'di-hash dan kewajiban ganti password benar-benar diterapkan.',
              style: TextStyle(
                color: Color(0xFF69778D),
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(generated ? 'Selesai' : 'Batal'),
        ),
        if (!generated)
          FilledButton(
            key: const Key('generate-temporary-password'),
            onPressed: _generatePreviewPassword,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF168B83),
            ),
            child: const Text('Buat password sementara'),
          ),
      ],
    );
  }
}

/// Menampilkan rentang akun serta tombol sebelumnya/berikutnya.
/// currentPage memakai indeks mulai dari 0; firstIndex/lastIndex untuk label.
class _UserPagination extends StatelessWidget {
  const _UserPagination({
    required this.currentPage,
    required this.pageCount,
    required this.firstIndex,
    required this.lastIndex,
    required this.totalUsers,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentPage;
  final int pageCount;
  final int firstIndex;
  final int lastIndex;
  final int totalUsers;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Menampilkan $firstIndex–$lastIndex dari $totalUsers pengguna',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        IconButton(
          key: const Key('user-page-previous'),
          tooltip: 'Halaman sebelumnya',
          onPressed: currentPage > 0 ? onPrevious : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text(
          '${currentPage + 1} / $pageCount',
          key: const Key('user-page-indicator'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        IconButton(
          key: const Key('user-page-next'),
          tooltip: 'Halaman berikutnya',
          onPressed: currentPage < pageCount - 1 ? onNext : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.onEdit,
    required this.onToggleActive,
  });

  final UserAccount user;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
              Expanded(child: _UserIdentity(user: user)),
              _UserActions(
                user: user,
                onEdit: onEdit,
                onToggleActive: onToggleActive,
              ),
            ],
          ),
          const Divider(height: 22),
          Row(
            children: [
              _RoleBadge(role: user.role),
              const Spacer(),
              _UserStatusBadge(isActive: user.isActive),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            'Login terakhir: ${_formatLogin(user.lastLoginAt)}',
            style: const TextStyle(color: Color(0xFF8994A7), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _EmptyUsers extends StatelessWidget {
  const _EmptyUsers();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          Icon(
            Icons.person_search_outlined,
            color: Color(0xFFADB7C5),
            size: 28,
          ),
          SizedBox(height: 8),
          Text(
            'Pengguna tidak ditemukan',
            style: TextStyle(
              color: Color(0xFF69778D),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Form tambah/edit akun; kata sandi hanya diminta ketika akun baru dibuat.
///
/// CATATAN PEMELIHARAAN: password dikembalikan terpisah dari UserAccount agar
/// tidak masuk state tabel atau model profil. Backend tetap meng-hash password.
class UserAccountDialog extends StatefulWidget {
  const UserAccountDialog({super.key, this.user});

  final UserAccount? user;

  @override
  State<UserAccountDialog> createState() => _UserAccountDialogState();
}

class _UserAccountDialogState extends State<UserAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late String _role;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user?.name ?? '');
    _usernameController = TextEditingController(
      text: widget.user?.username ?? '',
    );
    _passwordController = TextEditingController();
    _role = widget.user?.role ?? 'Petugas';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    // CATATAN: pop mengirim data hasil validasi ke parent; parent yang
    // memeriksa username duplikat dan menyimpan perubahan.
    final user = UserAccount(
      id: widget.user?.id ?? 'user-${DateTime.now().microsecondsSinceEpoch}',
      name: _nameController.text.trim(),
      username: _usernameController.text.trim(),
      role: _role,
      isActive: widget.user?.isActive ?? true,
      lastLoginAt: widget.user?.lastLoginAt,
    );
    Navigator.of(context).pop(
      UserAccountDraft(user: user, initialPassword: _passwordController.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.user == null ? 'Tambah Pengguna' : 'Ubah Pengguna',
        style: const TextStyle(
          color: Color(0xFF172B4D),
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('user-name-input'),
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nama lengkap'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Nama wajib diisi'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('user-username-input'),
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Username wajib diisi';
                    }
                    if (value.trim().contains(' ')) {
                      return 'Username tidak boleh mengandung spasi';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                if (widget.user == null) ...[
                  TextFormField(
                    key: const Key('user-initial-password-input'),
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Kata sandi awal',
                      helperText: 'Minimal 12 karakter; disimpan sebagai hash di server.',
                    ),
                    validator: (value) {
                      if (widget.user != null) return null;
                      if (value == null ||
                          value.runes.length < 12 ||
                          value.runes.length > 128) {
                        return 'Kata sandi harus 12–128 karakter';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                ],
                DropdownButtonFormField<String>(
                  key: const Key('user-role-input'),
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Peran'),
                  items: const ['Admin', 'Petugas', 'Pimpinan']
                      .map(
                        (role) =>
                            DropdownMenuItem(value: role, child: Text(role)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _role = value);
                  },
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.user == null
                        ? 'Kata sandi awal dikirim hanya saat membuat akun dan tidak ditampilkan kembali.'
                        : 'Kata sandi akun tidak dapat dilihat atau diubah dari form profil.',
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
          key: const Key('save-user'),
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF168B83),
          ),
          child: Text(
            widget.user == null ? 'Simpan pengguna' : 'Simpan perubahan',
          ),
        ),
      ],
    );
  }
}

String _formatLogin(DateTime? date) {
  if (date == null) return 'Belum pernah login';
  final local = date.toLocal();
  final month = const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ][local.month - 1];
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} $month ${local.year}, $hour:$minute';
}
