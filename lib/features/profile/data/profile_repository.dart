import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_exception_mapper.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../../../shared/models/user_profile.dart';

abstract interface class IProfileRepository {
  Future<UserProfile?> getCurrentProfile();
  Future<UserProfile> updateProfile({
    String? fullName,
    String? avatarUrl,
    DateTime? dateOfBirth,
  });
}

class SupabaseProfileRepository implements IProfileRepository {
  SupabaseProfileRepository({required SupabaseClient supabaseClient})
    : _supabase = supabaseClient;

  final SupabaseClient _supabase;

  @override
  Future<UserProfile?> getCurrentProfile() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return null;

    try {
      final response = await _supabase
          .from(SupabaseTables.profiles)
          .select()
          .eq('id', uid)
          .maybeSingle();

      if (response == null) return null;
      return UserProfile.fromJson(response);
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<UserProfile> updateProfile({
    String? fullName,
    String? avatarUrl,
    DateTime? dateOfBirth,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      throw const AppException('Must be authenticated to update profile.');
    }

    final updateData = <String, dynamic>{};
    if (fullName != null) updateData['full_name'] = fullName.trim();
    if (avatarUrl != null) updateData['avatar_url'] = avatarUrl.trim();
    if (dateOfBirth != null) {
      updateData['date_of_birth'] = dateOfBirth.toIso8601String().substring(
        0,
        10,
      );
    }

    if (updateData.isEmpty) {
      final existing = await getCurrentProfile();
      if (existing == null) {
        throw const AppException('Profile not found.');
      }
      return existing;
    }

    try {
      final response = await _supabase
          .from(SupabaseTables.profiles)
          .update(updateData)
          .eq('id', uid)
          .select()
          .single();

      return UserProfile.fromJson(response);
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }
}

final profileRepositoryProvider = Provider<IProfileRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return SupabaseProfileRepository(supabaseClient: supabase);
});

final userProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final repo = ref.watch(profileRepositoryProvider);
  return repo.getCurrentProfile();
});
