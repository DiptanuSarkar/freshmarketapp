import 'package:flutter_riverpod/flutter_riverpod.dart';

class WishlistNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    return {'prod_chk_curry', 'prod_fish_seer'};
  }

  void toggle(String productId) {
    if (state.contains(productId)) {
      state = Set.from(state)..remove(productId);
    } else {
      state = Set.from(state)..add(productId);
    }
  }

  bool isFavorite(String productId) => state.contains(productId);
}

final wishlistProvider = NotifierProvider<WishlistNotifier, Set<String>>(
  WishlistNotifier.new,
);
