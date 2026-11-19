import 'package:flutter/material.dart';

import 'app_footer.dart';

/// Navigasi samping bersama. Ubah daftar menu di sini agar konsisten di semua
/// halaman; [onSelect] menangani perpindahan halaman dari pemanggil.
/// CATATAN PEMELIHARAAN: nama pada [_sections] dan [_masters] dikirim persis
/// lewat [onSelect], jadi label harus sesuai dengan pemetaan halaman pemanggil.
class AppNavbar extends StatelessWidget {
  const AppNavbar({
    super.key,
    required this.selectedPage,
    required this.onSelect,
    required this.canManageUsers,
    required this.canViewMasterData,
    this.schoolName = 'SMP Negeri 1',
    this.academicYear = '2025/2026',
  });

  final String selectedPage;
  final ValueChanged<String> onSelect;
  final bool canManageUsers;
  final bool canViewMasterData;
  final String schoolName;
  final String academicYear;

  static const _sections = <_NavEntry>[
    _NavEntry('Dashboard', Icons.grid_view_rounded),
    _NavEntry('Inventaris', Icons.inventory_2_outlined),
    _NavEntry('Mutasi Barang', Icons.swap_horiz_rounded),
    _NavEntry('Pemeliharaan', Icons.home_repair_service_outlined),
    _NavEntry('Laporan', Icons.bar_chart_rounded),
  ];

  static const _masters = <_NavEntry>[
    _NavEntry('Jenis & Kategori', Icons.category_outlined),
    _NavEntry('Lokasi', Icons.location_on_outlined),
  ];
  static const _usersEntry = _NavEntry(
    'Pengguna',
    Icons.people_outline_rounded,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: const Color(0xFF172B4D),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 20, 30),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF20A69A),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.inventory_2_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RuangSarana',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'INVENTARIS SEKOLAH',
                          style: TextStyle(
                            color: Color(0xFF9BAAC1),
                            fontSize: 9,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 16, 10),
              child: Text(
                'MENU UTAMA',
                style: TextStyle(
                  color: Color(0xFF8495AF),
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ..._sections.map(_buildNavItem),
            if (canViewMasterData || canManageUsers) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 16, 10),
                child: Text(
                  'PENGELOLAAN',
                  style: TextStyle(
                    color: Color(0xFF8495AF),
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (canViewMasterData) ..._masters.map(_buildNavItem),
              if (canManageUsers) _buildNavItem(_usersEntry),
            ],
            const Spacer(),
            AppFooter(schoolName: schoolName, academicYear: academicYear),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(_NavEntry entry) {
    final selected = selectedPage == entry.label;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? const Color(0xFF24436C) : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => onSelect(entry.label),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                if (selected)
                  Container(
                    width: 3,
                    height: 25,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF45C2B5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  )
                else
                  const SizedBox(width: 15),
                Icon(
                  entry.icon,
                  size: 19,
                  color: selected
                      ? const Color(0xFF7DD5CB)
                      : const Color(0xFF9BAAC1),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFFC1CAD8),
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavEntry {
  const _NavEntry(this.label, this.icon);

  final String label;
  final IconData icon;
}
