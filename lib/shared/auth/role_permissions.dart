// CATATAN PEMELIHARAAN: matriks ini mengatur menu dan aksi Flutter; setiap
// endpoint backend baru tetap harus menegakkan izin yang sama di server.
class RolePermissions {
  const RolePermissions({
    required this.canManageUsers,
    required this.canViewMasterData,
    required this.canManageMasterData,
    required this.canManageAssets,
    required this.canPrintAssetLabels,
    required this.canManageMovements,
    required this.canManageMaintenance,
    required this.canExportReports,
  });

  factory RolePermissions.fromRole(String role) {
    return switch (role.toLowerCase()) {
      'admin' => const RolePermissions(
        canManageUsers: true,
        canViewMasterData: true,
        canManageMasterData: true,
        canManageAssets: true,
        canPrintAssetLabels: true,
        canManageMovements: true,
        canManageMaintenance: true,
        canExportReports: true,
      ),
      'petugas' => const RolePermissions(
        canManageUsers: false,
        canViewMasterData: false,
        canManageMasterData: false,
        canManageAssets: true,
        canPrintAssetLabels: true,
        canManageMovements: true,
        canManageMaintenance: true,
        canExportReports: false,
      ),
      'pimpinan' => const RolePermissions(
        canManageUsers: false,
        canViewMasterData: true,
        canManageMasterData: false,
        canManageAssets: false,
        canPrintAssetLabels: false,
        canManageMovements: false,
        canManageMaintenance: false,
        canExportReports: true,
      ),
      _ => const RolePermissions(
        canManageUsers: false,
        canViewMasterData: false,
        canManageMasterData: false,
        canManageAssets: false,
        canPrintAssetLabels: false,
        canManageMovements: false,
        canManageMaintenance: false,
        canExportReports: false,
      ),
    };
  }

  final bool canManageUsers;
  final bool canViewMasterData;
  final bool canManageMasterData;
  final bool canManageAssets;
  final bool canPrintAssetLabels;
  final bool canManageMovements;
  final bool canManageMaintenance;
  final bool canExportReports;
}
