import 'dart:convert';

import 'package:web/web.dart' as web;

import 'session_storage_contract.dart';

SessionStorage createSessionStorage() => _WebSessionStorage();

class _WebSessionStorage implements SessionStorage {
  static const _storageKey = 'ruangsarana.api_session.v1';

  // CATATAN PEMELIHARAAN: sessionStorage bertahan saat reload tetapi hilang
  // saat tab ditutup; token tetap dapat dibaca JavaScript, jadi produksi yang
  // lebih ketat sebaiknya memindahkan sesi ke cookie HttpOnly di backend.
  @override
  Future<PersistedApiSession?> read() async {
    try {
      final value = web.window.sessionStorage.getItem(_storageKey);
      if (value == null) return null;

      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic> ||
          decoded['access_token'] is! String ||
          decoded['expires_at'] is! String) {
        throw const SessionStorageException(
          'Data sesi di browser tidak valid. Hapus sesi lalu masuk kembali.',
        );
      }
      final expiresAt = DateTime.tryParse(decoded['expires_at'] as String);
      if (expiresAt == null) {
        throw const SessionStorageException(
          'Masa berlaku sesi di browser tidak valid. Hapus sesi lalu masuk kembali.',
        );
      }
      return PersistedApiSession(
        accessToken: decoded['access_token'] as String,
        expiresAt: expiresAt,
      );
    } on SessionStorageException {
      rethrow;
    } on FormatException catch (error) {
      throw SessionStorageException(
        'Data sesi di browser tidak dapat dibaca: $error',
      );
    } catch (error) {
      throw SessionStorageException(
        'Penyimpanan sesi browser tidak dapat diakses: $error',
      );
    }
  }

  @override
  Future<void> write(PersistedApiSession session) async {
    try {
      web.window.sessionStorage.setItem(
        _storageKey,
        jsonEncode({
          'access_token': session.accessToken,
          'expires_at': session.expiresAt.toUtc().toIso8601String(),
        }),
      );
    } catch (error) {
      throw SessionStorageException(
        'Sesi tidak dapat disimpan di browser: $error',
      );
    }
  }

  @override
  Future<void> clear() async {
    try {
      web.window.sessionStorage.removeItem(_storageKey);
    } catch (error) {
      throw SessionStorageException('Sesi browser tidak dapat dihapus: $error');
    }
  }
}
