import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

/// Secrets in the Keychain / Android Keystore: the Supabase session and the local cache key.
class SecureStorageService extends GetxService {
  SecureStorageService({FlutterSecureStorage? storage}) : storage = storage ?? defaultStorage;

  static SecureStorageService get to => Get.find();

  /// "This device only": a session or key is never restored onto another phone (one active phone per user).
  static const defaultStorage = FlutterSecureStorage(iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device));

  static const cacheKeyName = 'hive_cache_key';

  final FlutterSecureStorage storage;

  /// AES cipher for the local cache boxes; the key never leaves secure storage.
  late final HiveAesCipher cacheCipher;

  /// True when the key was just created: any cache box left from an older key can't be read and must be cleared.
  late final bool cacheKeyIsNew;

  Future<SecureStorageService> init() async {
    final (key, isNew) = await loadCacheKey(storage);
    cacheCipher = HiveAesCipher(key);
    cacheKeyIsNew = isNew;
    return this;
  }

  /// The saved 32-byte key, or a new one when none (or a damaged one) is saved.
  static Future<(List<int>, bool)> loadCacheKey(FlutterSecureStorage storage) async {
    final saved = await storage.read(key: cacheKeyName);
    if (saved != null) {
      try {
        final key = base64Decode(saved);
        if (key.length == 32) return (key, false);
      } on FormatException {
        // damaged: replaced below
      }
    }
    final key = Hive.generateSecureKey();
    await storage.write(key: cacheKeyName, value: base64Encode(key));
    return (key, true);
  }
}
