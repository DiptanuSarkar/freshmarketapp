import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_exception_mapper.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../../../shared/models/address.dart';

abstract interface class IAddressRepository {
  Future<List<UserAddress>> getAddresses();
  Future<UserAddress> addAddress(UserAddress address);
  Future<UserAddress> updateAddress(UserAddress address);
  Future<void> deleteAddress(String addressId);
  Future<void> setDefaultAddress(String addressId);
}

class SupabaseAddressRepository implements IAddressRepository {
  SupabaseAddressRepository({required SupabaseClient supabaseClient})
    : _supabase = supabaseClient;

  final SupabaseClient _supabase;

  @override
  Future<List<UserAddress>> getAddresses() async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return [];

    try {
      final response = await _supabase
          .from(SupabaseTables.addresses)
          .select()
          .eq('user_id', uid)
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);

      final List<dynamic> list = response;
      return list
          .map((item) => UserAddress.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<UserAddress> addAddress(UserAddress address) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      throw const AppException('Must be signed in to save addresses.');
    }

    try {
      // If setting as default, clear any existing default first to avoid unique constraint conflict
      if (address.isDefault) {
        await _supabase
            .from(SupabaseTables.addresses)
            .update({'is_default': false})
            .eq('user_id', uid)
            .eq('is_default', true);
      }

      final insertData = address.toInsertJson(uid);
      final response = await _supabase
          .from(SupabaseTables.addresses)
          .insert(insertData)
          .select()
          .single();

      return UserAddress.fromJson(response);
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<UserAddress> updateAddress(UserAddress address) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      throw const AppException('Must be signed in to update addresses.');
    }

    try {
      if (address.isDefault) {
        // Clear other defaults first
        await _supabase
            .from(SupabaseTables.addresses)
            .update({'is_default': false})
            .eq('user_id', uid)
            .neq('id', address.id)
            .eq('is_default', true);
      }

      final updateData = {
        'label': address.tag,
        'recipient_name': address.recipientName,
        'phone': address.phone,
        'address_line1': address.houseOrFlat,
        'address_line2': address.streetOrArea,
        'city': address.city,
        'state': address.state,
        'pincode': address.pincode,
        'landmark': address.landmark,
        'delivery_instructions': address.deliveryInstructions,
        'latitude': address.latitude,
        'longitude': address.longitude,
        'is_default': address.isDefault,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final response = await _supabase
          .from(SupabaseTables.addresses)
          .update(updateData)
          .eq('id', address.id)
          .eq('user_id', uid)
          .select()
          .single();

      return UserAddress.fromJson(response);
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<void> deleteAddress(String addressId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    try {
      await _supabase
          .from(SupabaseTables.addresses)
          .delete()
          .eq('id', addressId)
          .eq('user_id', uid);
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }

  @override
  Future<void> setDefaultAddress(String addressId) async {
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;

    try {
      // Step 1: Clear existing default
      await _supabase
          .from(SupabaseTables.addresses)
          .update({'is_default': false})
          .eq('user_id', uid)
          .eq('is_default', true);

      // Step 2: Set chosen address as default
      await _supabase
          .from(SupabaseTables.addresses)
          .update({
            'is_default': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', addressId)
          .eq('user_id', uid);
    } catch (e) {
      throw SupabaseExceptionMapper.map(e);
    }
  }
}

final addressRepositoryProvider = Provider<IAddressRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return SupabaseAddressRepository(supabaseClient: supabase);
});
