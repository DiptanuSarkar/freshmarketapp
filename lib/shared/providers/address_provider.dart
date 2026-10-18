import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_client_provider.dart';
import '../../features/address/data/address_repository.dart';
import '../models/address.dart';

enum AddressFetchStatus { initial, loading, success, error }

class AddressFetchState {
  const AddressFetchState({
    this.status = AddressFetchStatus.initial,
    this.errorMessage,
  });

  final AddressFetchStatus status;
  final String? errorMessage;

  bool get isLoading => status == AddressFetchStatus.loading;
  bool get hasError => status == AddressFetchStatus.error;
  bool get isSuccess => status == AddressFetchStatus.success;
}

class AddressFetchStateNotifier extends Notifier<AddressFetchState> {
  @override
  AddressFetchState build() {
    return const AddressFetchState(status: AddressFetchStatus.loading);
  }

  void update(AddressFetchState newState) {
    state = newState;
  }
}

final addressFetchStateProvider =
    NotifierProvider<AddressFetchStateNotifier, AddressFetchState>(
      AddressFetchStateNotifier.new,
    );

class AddressNotifier extends Notifier<List<UserAddress>> {
  @override
  List<UserAddress> build() {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      ref
          .read(addressFetchStateProvider.notifier)
          .update(const AddressFetchState(status: AddressFetchStatus.success));
      return const [];
    }

    Future.microtask(() => loadAddresses());
    return const [];
  }

  Future<void> loadAddresses() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      state = const [];
      ref
          .read(addressFetchStateProvider.notifier)
          .update(const AddressFetchState(status: AddressFetchStatus.success));
      return;
    }

    ref
        .read(addressFetchStateProvider.notifier)
        .update(const AddressFetchState(status: AddressFetchStatus.loading));

    try {
      final repo = ref.read(addressRepositoryProvider);
      final list = await repo.getAddresses();
      state = list;
      ref
          .read(addressFetchStateProvider.notifier)
          .update(const AddressFetchState(status: AddressFetchStatus.success));
    } catch (e) {
      ref
          .read(addressFetchStateProvider.notifier)
          .update(
            AddressFetchState(
              status: AddressFetchStatus.error,
              errorMessage: e.toString(),
            ),
          );
    }
  }

  UserAddress? get defaultAddress {
    if (state.isEmpty) return null;
    return state.firstWhere((a) => a.isDefault, orElse: () => state.first);
  }

  Future<void> setDefault(String addressId) async {
    final previous = List<UserAddress>.from(state);
    state = state.map((a) => a.copyWith(isDefault: a.id == addressId)).toList();

    try {
      final repo = ref.read(addressRepositoryProvider);
      await repo.setDefaultAddress(addressId);
    } catch (e) {
      state = previous; // Rollback
    }
  }

  Future<void> addAddress(UserAddress newAddress) async {
    final previous = List<UserAddress>.from(state);
    try {
      final repo = ref.read(addressRepositoryProvider);
      final created = await repo.addAddress(newAddress);
      if (created.isDefault) {
        state = [created, ...state.map((a) => a.copyWith(isDefault: false))];
      } else {
        state = [...state, created];
      }
    } catch (e) {
      state = previous;
      rethrow;
    }
  }

  Future<void> updateAddress(UserAddress address) async {
    final previous = List<UserAddress>.from(state);
    try {
      final repo = ref.read(addressRepositoryProvider);
      final updated = await repo.updateAddress(address);
      state = state
          .map(
            (a) => a.id == updated.id
                ? updated
                : (updated.isDefault ? a.copyWith(isDefault: false) : a),
          )
          .toList();
    } catch (e) {
      state = previous;
      rethrow;
    }
  }

  Future<void> deleteAddress(String addressId) async {
    final previous = List<UserAddress>.from(state);
    state = state.where((a) => a.id != addressId).toList();

    try {
      final repo = ref.read(addressRepositoryProvider);
      await repo.deleteAddress(addressId);
    } catch (e) {
      state = previous;
    }
  }
}

final addressProvider = NotifierProvider<AddressNotifier, List<UserAddress>>(
  AddressNotifier.new,
);

final selectedAddressProvider = Provider<UserAddress?>((ref) {
  final addresses = ref.watch(addressProvider);
  if (addresses.isEmpty) return null;
  return addresses.firstWhere(
    (a) => a.isDefault,
    orElse: () => addresses.first,
  );
});
