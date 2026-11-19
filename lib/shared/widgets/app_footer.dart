import 'package:flutter/material.dart';

/// Identitas sekolah ditentukan oleh pemanggil agar bisa digunakan ulang
/// tanpa mengubah isi widget saat nama sekolah atau tahun ajaran berubah.
class AppFooter extends StatelessWidget {
  const AppFooter({
    super.key,
    required this.schoolName,
    required this.academicYear,
  });

  final String schoolName;
  final String academicYear;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF223A60),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.school_outlined, color: Color(0xFF7DD5CB), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schoolName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Tahun ajaran $academicYear',
                  style: const TextStyle(
                    color: Color(0xFF9BAAC1),
                    fontSize: 10,
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
