import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_exception_mapper.dart';
import '../../../core/supabase/supabase_tables.dart';

abstract class ISupportRepository {
  Future<void> submitContactMessage({
    required String name,
    String? email,
    String? phone,
    String? subject,
    required String message,
  });
}

class SupabaseSupportRepository implements ISupportRepository {
  SupabaseSupportRepository(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<void> submitContactMessage({
    required String name,
    String? email,
    String? phone,
    String? subject,
    required String message,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      await _supabase.from(SupabaseTables.contactMessages).insert({
        'user_id': user?.id,
        'name': name.trim(),
        'email': (email != null && email.trim().isNotEmpty)
            ? email.trim()
            : user?.email,
        'phone': (phone != null && phone.trim().isNotEmpty)
            ? phone.trim()
            : null,
        'subject': (subject != null && subject.trim().isNotEmpty)
            ? subject.trim()
            : 'Customer Support Message',
        'message': message.trim(),
        'status': 'new',
      });
    } catch (e, stackTrace) {
      throw SupabaseExceptionMapper.map(e, stackTrace);
    }
  }
}

final supportRepositoryProvider = Provider<ISupportRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return SupabaseSupportRepository(supabase);
});
