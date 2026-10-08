import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_exception_mapper.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../../../shared/models/coupon.dart';

abstract interface class ICouponRepository {
  Future<List<Coupon>> getActiveCoupons();
  Future<Coupon?> getCouponByCode(String code);
}

class SupabaseCouponRepository implements ICouponRepository {
  SupabaseCouponRepository({required SupabaseClient supabaseClient})
    : _supabase = supabaseClient;

  final SupabaseClient _supabase;

  @override
  Future<List<Coupon>> getActiveCoupons() async {
    try {
      final now = DateTime.now().toIso8601String();
      final response = await _supabase
          .from(SupabaseTables.coupons)
          .select()
          .eq('is_active', true)
          .eq('is_public', true)
          .or('starts_at.is.null,starts_at.lte.$now')
          .or('ends_at.is.null,ends_at.gte.$now');

      final List<dynamic> list = response;
      return list
          .map((item) => Coupon.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<Coupon?> getCouponByCode(String code) async {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) return null;

    try {
      final now = DateTime.now().toIso8601String();
      final response = await _supabase
          .from(SupabaseTables.coupons)
          .select()
          .eq('code', cleanCode)
          .eq('is_active', true)
          .or('starts_at.is.null,starts_at.lte.$now')
          .or('ends_at.is.null,ends_at.gte.$now')
          .maybeSingle();

      if (response == null) return null;
      return Coupon.fromJson(response);
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }
}

final couponRepositoryProvider = Provider<ICouponRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return SupabaseCouponRepository(supabaseClient: supabase);
});

final availableCouponsProvider = FutureProvider<List<Coupon>>((ref) async {
  final repo = ref.watch(couponRepositoryProvider);
  return repo.getActiveCoupons();
});
