import 'session_storage_contract.dart';
import 'session_storage_memory.dart'
    if (dart.library.js_interop) 'session_storage_web.dart'
    as platform;

export 'session_storage_contract.dart';

SessionStorage createSessionStorage() => platform.createSessionStorage();
