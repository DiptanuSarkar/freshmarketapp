import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_exception_mapper.dart';
import '../../../core/supabase/supabase_tables.dart';

abstract class IAppSettingsRepository {
  Future<Map<String, dynamic>> getPublicSettings();
  Future<dynamic> getSetting(String key);
}

class SupabaseAppSettingsRepository implements IAppSettingsRepository {
  SupabaseAppSettingsRepository(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<Map<String, dynamic>> getPublicSettings() async {
    try {
      final data = await _supabase
          .from(SupabaseTables.appSettings)
          .select('key, value')
          .eq('is_public', true);

      final result = <String, dynamic>{};
      for (final row in data as List<dynamic>) {
        final key = row['key'] as String;
        result[key] = row['value'];
      }
      return result;
    } catch (e, stackTrace) {
      throw SupabaseExceptionMapper.map(e, stackTrace);
    }
  }

  @override
  Future<dynamic> getSetting(String key) async {
    try {
      final res = await _supabase
          .from(SupabaseTables.appSettings)
          .select('value')
          .eq('key', key)
          .eq('is_public', true)
          .maybeSingle();

      return res?['value'];
    } catch (e, stackTrace) {
      throw SupabaseExceptionMapper.map(e, stackTrace);
    }
  }
}

final appSettingsRepositoryProvider = Provider<IAppSettingsRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return SupabaseAppSettingsRepository(supabase);
});

final appSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final repo = ref.watch(appSettingsRepositoryProvider);
  return repo.getPublicSettings();
});
