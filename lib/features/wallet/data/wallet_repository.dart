import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_exception_mapper.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../../../shared/models/wallet_transaction.dart';

abstract class IWalletRepository {
  Future<double> getBalance();
  Future<List<WalletTransaction>> getTransactions();
}

class SupabaseWalletRepository implements IWalletRepository {
  SupabaseWalletRepository(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<double> getBalance() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return 0.0;

      final res = await _supabase
          .from(SupabaseTables.walletAccounts)
          .select('balance')
          .eq('user_id', user.id)
          .maybeSingle();

      if (res == null) return 0.0;
      return (res['balance'] as num?)?.toDouble() ?? 0.0;
    } catch (e, stackTrace) {
      throw SupabaseExceptionMapper.map(e, stackTrace);
    }
  }

  @override
  Future<List<WalletTransaction>> getTransactions() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final data = await _supabase
          .from(SupabaseTables.walletTransactions)
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final list = data as List<dynamic>;
      return list
          .map(
            (json) => WalletTransaction.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (e, stackTrace) {
      throw SupabaseExceptionMapper.map(e, stackTrace);
    }
  }
}

final walletRepositoryProvider = Provider<IWalletRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return SupabaseWalletRepository(supabase);
});

final walletBalanceProvider = FutureProvider<double>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return 0.0;
  final repo = ref.watch(walletRepositoryProvider);
  return repo.getBalance();
});

final walletTransactionsProvider = FutureProvider<List<WalletTransaction>>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final repo = ref.watch(walletRepositoryProvider);
  return repo.getTransactions();
});
