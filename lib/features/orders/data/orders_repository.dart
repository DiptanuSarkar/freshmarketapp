import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_exception_mapper.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../../../shared/models/order.dart';

abstract class IOrdersRepository {
  Future<List<CustomerOrder>> getOrders();
  Future<CustomerOrder?> getOrderById(String orderId);
}

class SupabaseOrdersRepository implements IOrdersRepository {
  SupabaseOrdersRepository(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<List<CustomerOrder>> getOrders() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final data = await _supabase
          .from(SupabaseTables.orders)
          .select('''
            *,
            order_items (
              *,
              variant:product_variants (
                product_id,
                products (
                  product_images (
                    image_url,
                    display_order
                  )
                )
              )
            ),
            order_status_history (*),
            payments (*)
          ''')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final list = data as List<dynamic>;
      return list
          .map((json) => CustomerOrder.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e, stackTrace) {
      throw SupabaseExceptionMapper.map(e, stackTrace);
    }
  }

  @override
  Future<CustomerOrder?> getOrderById(String orderId) async {
    try {
      final data = await _supabase
          .from(SupabaseTables.orders)
          .select('''
            *,
            order_items (
              *,
              variant:product_variants (
                product_id,
                products (
                  product_images (
                    image_url,
                    display_order
                  )
                )
              )
            ),
            order_status_history (*),
            payments (*)
          ''')
          .eq('id', orderId)
          .maybeSingle();

      if (data == null) return null;
      return CustomerOrder.fromJson(data);
    } catch (e, stackTrace) {
      throw SupabaseExceptionMapper.map(e, stackTrace);
    }
  }
}

final ordersRepositoryProvider = Provider<IOrdersRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return SupabaseOrdersRepository(supabase);
});

final customerOrdersProvider = FutureProvider<List<CustomerOrder>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final repo = ref.watch(ordersRepositoryProvider);
  return repo.getOrders();
});

final orderDetailProvider = FutureProvider.family<CustomerOrder?, String>((
  ref,
  id,
) async {
  final repo = ref.watch(ordersRepositoryProvider);
  return repo.getOrderById(id);
});
