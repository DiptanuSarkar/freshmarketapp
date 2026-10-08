import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_exception_mapper.dart';
import '../../../core/supabase/supabase_tables.dart';

abstract interface class IWishlistRepository {
  Future<Set<String>> getWishlistProductIds();
  Future<void> addToWishlist(String productId);
  Future<void> removeFromWishlist(String productId);
}

class SupabaseWishlistRepository implements IWishlistRepository {
  SupabaseWishlistRepository({required SupabaseClient supabaseClient})
    : _supabase = supabaseClient;

  final SupabaseClient _supabase;

  @override
  Future<Set<String>> getWishlistProductIds() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return {};

    try {
      final response = await _supabase
          .from(SupabaseTables.wishlistItems)
          .select('product_id')
          .eq('user_id', uid);

      final List<dynamic> list = response;
      return list
          .map((item) => (item as Map<String, dynamic>)['product_id'] as String)
          .toSet();
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<void> addToWishlist(String productId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      throw const AppException('Please sign in to add items to your wishlist.');
    }

    try {
      await _supabase.from(SupabaseTables.wishlistItems).upsert({
        'user_id': uid,
        'product_id': productId,
      }, onConflict: 'user_id,product_id');
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<void> removeFromWishlist(String productId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    try {
      await _supabase
          .from(SupabaseTables.wishlistItems)
          .delete()
          .eq('user_id', uid)
          .eq('product_id', productId);
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }
}

final wishlistRepositoryProvider = Provider<IWishlistRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return SupabaseWishlistRepository(supabaseClient: supabase);
});
