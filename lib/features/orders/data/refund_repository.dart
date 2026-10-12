import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_exception_mapper.dart';
import '../../../shared/models/refund.dart';

abstract class IRefundRepository {
  Future<RefundModel?> checkRefundStatus(String orderId);
}

class SupabaseRefundRepository implements IRefundRepository {
  SupabaseRefundRepository(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<RefundModel?> checkRefundStatus(String orderId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw StateError('User not authenticated.');
      }

      final response = await _supabase.functions.invoke(
        'check-refund-status',
        body: {'order_id': orderId},
      );

      final data = response.data;
      if (data is Map<String, dynamic> && data['success'] == true) {
        final refundJson = data['refund'];
        if (refundJson is Map<String, dynamic>) {
          return RefundModel.fromJson(refundJson);
        }
      }
      return null;
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map<String, dynamic> && details['message'] != null) {
        throw Exception(details['message']);
      }
      throw SupabaseExceptionMapper.map(e);
    } catch (e, stackTrace) {
      throw SupabaseExceptionMapper.map(e, stackTrace);
    }
  }
}

final refundRepositoryProvider = Provider<IRefundRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return SupabaseRefundRepository(supabase);
});
