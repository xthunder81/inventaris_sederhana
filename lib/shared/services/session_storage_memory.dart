import 'session_storage_contract.dart';

// CATATAN PEMELIHARAAN: selain Web, sesi hanya hidup selama proses aplikasi;
// tambahkan secure storage native bila kebutuhan persistensi platform berubah.
SessionStorage createSessionStorage() => _MemorySessionStorage();

class _MemorySessionStorage implements SessionStorage {
  PersistedApiSession? _session;

  @override
  Future<PersistedApiSession?> read() async => _session;

  @override
  Future<void> write(PersistedApiSession session) async {
    _session = session;
  }

  @override
  Future<void> clear() async {
    _session = null;
  }
}
