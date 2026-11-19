class PersistedApiSession {
  const PersistedApiSession({
    required this.accessToken,
    required this.expiresAt,
  });

  final String accessToken;
  final DateTime expiresAt;
}

abstract interface class SessionStorage {
  Future<PersistedApiSession?> read();

  Future<void> write(PersistedApiSession session);

  Future<void> clear();
}

class SessionStorageException implements Exception {
  const SessionStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}
