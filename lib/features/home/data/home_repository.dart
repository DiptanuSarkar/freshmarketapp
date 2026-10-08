import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_exception_mapper.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../../../shared/models/banner_item.dart';

abstract interface class IHomeRepository {
  Future<List<BannerItem>> getActiveBanners();
}

class SupabaseHomeRepository implements IHomeRepository {
  SupabaseHomeRepository({required SupabaseClient supabaseClient})
    : _supabase = supabaseClient;

  final SupabaseClient _supabase;

  @override
  Future<List<BannerItem>> getActiveBanners() async {
    try {
      final response = await _supabase
          .from(SupabaseTables.banners)
          .select()
          .eq('is_active', true)
          .order('display_order', ascending: true);

      final List<dynamic> list = response;
      return list
          .map((item) => BannerItem.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }
}

final homeRepositoryProvider = Provider<IHomeRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return SupabaseHomeRepository(supabaseClient: supabase);
});

final homeBannersProvider = FutureProvider<List<BannerItem>>((ref) async {
  final repo = ref.watch(homeRepositoryProvider);
  return repo.getActiveBanners();
});
