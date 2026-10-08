import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_exception_mapper.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../../../shared/models/delivery_slot.dart';
import '../../../shared/models/service_area.dart';

abstract interface class IDeliveryRepository {
  Future<ServiceArea?> checkServiceability(String pincode);
  Future<List<DeliverySlot>> getActiveDeliverySlots();
}

class SupabaseDeliveryRepository implements IDeliveryRepository {
  SupabaseDeliveryRepository({required SupabaseClient supabaseClient})
    : _supabase = supabaseClient;

  final SupabaseClient _supabase;

  @override
  Future<ServiceArea?> checkServiceability(String pincode) async {
    final cleanPincode = pincode.trim();
    if (cleanPincode.isEmpty) return null;

    try {
      final response = await _supabase
          .from(SupabaseTables.serviceAreas)
          .select()
          .eq('pincode', cleanPincode)
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) return null;
      return ServiceArea.fromJson(response);
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<List<DeliverySlot>> getActiveDeliverySlots() async {
    try {
      final response = await _supabase
          .from(SupabaseTables.deliverySlots)
          .select()
          .eq('is_active', true)
          .order('start_time', ascending: true);

      final List<dynamic> list = response;
      return list
          .map((item) => DeliverySlot.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }
}

final deliveryRepositoryProvider = Provider<IDeliveryRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return SupabaseDeliveryRepository(supabaseClient: supabase);
});

final deliverySlotsProvider = FutureProvider<List<DeliverySlot>>((ref) async {
  final repo = ref.watch(deliveryRepositoryProvider);
  return repo.getActiveDeliverySlots();
});

final serviceAreaByPincodeProvider =
    FutureProvider.family<ServiceArea?, String>((ref, pincode) async {
      final repo = ref.watch(deliveryRepositoryProvider);
      return repo.checkServiceability(pincode);
    });
