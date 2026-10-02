import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mock_data.dart';
import '../models/address.dart';

class AddressNotifier extends Notifier<List<UserAddress>> {
  @override
  List<UserAddress> build() {
    return MockData.addresses;
  }

  UserAddress get defaultAddress =>
      state.firstWhere((a) => a.isDefault, orElse: () => state.first);

  void setDefault(String addressId) {
    state = state.map((a) {
      return UserAddress(
        id: a.id,
        tag: a.tag,
        recipientName: a.recipientName,
        phone: a.phone,
        houseOrFlat: a.houseOrFlat,
        streetOrArea: a.streetOrArea,
        city: a.city,
        pincode: a.pincode,
        landmark: a.landmark,
        latitude: a.latitude,
        longitude: a.longitude,
        isDefault: a.id == addressId,
      );
    }).toList();
  }

  void addAddress(UserAddress newAddress) {
    state = [...state, newAddress];
  }
}

final addressProvider = NotifierProvider<AddressNotifier, List<UserAddress>>(
  AddressNotifier.new,
);

final selectedAddressProvider = Provider<UserAddress>((ref) {
  final addresses = ref.watch(addressProvider);
  return addresses.firstWhere(
    (a) => a.isDefault,
    orElse: () => addresses.first,
  );
});
