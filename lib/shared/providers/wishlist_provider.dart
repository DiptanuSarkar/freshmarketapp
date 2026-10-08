import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_client_provider.dart';
import '../../features/wishlist/data/wishlist_repository.dart';

class WishlistNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const {};
    }

    // Trigger async load
    Future.microtask(() => loadWishlist());
    return const {};
  }

  Future<void> loadWishlist() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      final repo = ref.read(wishlistRepositoryProvider);
      final items = await repo.getWishlistProductIds();
      state = items;
    } catch (_) {
      // Keep existing state on transient error
    }
  }

  Future<bool> toggle(String productId) async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      return false; // Indicates login required
    }

    final repo = ref.read(wishlistRepositoryProvider);
    final previous = Set<String>.from(state);

    if (state.contains(productId)) {
      // Optimistic remove
      state = Set.from(state)..remove(productId);
      try {
        await repo.removeFromWishlist(productId);
        return true;
      } catch (e) {
        state = previous; // Rollback
        return false;
      }
    } else {
      // Optimistic add
      state = Set.from(state)..add(productId);
      try {
        await repo.addToWishlist(productId);
        return true;
      } catch (e) {
        state = previous; // Rollback
        return false;
      }
    }
  }

  bool isFavorite(String productId) => state.contains(productId);
}

final wishlistProvider = NotifierProvider<WishlistNotifier, Set<String>>(
  WishlistNotifier.new,
);
