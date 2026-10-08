import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/supabase/supabase_exception_mapper.dart';
import '../../../core/supabase/supabase_tables.dart';
import '../../../shared/models/notification_item.dart';

abstract class INotificationsRepository {
  Future<List<NotificationItem>> getNotifications();
  Future<int> getUnreadCount();
  Future<void> markAsRead(String notificationId);
  Future<void> markAllAsRead();
}

class SupabaseNotificationsRepository implements INotificationsRepository {
  SupabaseNotificationsRepository(this._supabase);

  final SupabaseClient _supabase;

  @override
  Future<List<NotificationItem>> getNotifications() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final data = await _supabase
          .from(SupabaseTables.notifications)
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final list = data as List<dynamic>;
      return list
          .map(
            (json) => NotificationItem.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (e, stackTrace) {
      throw SupabaseExceptionMapper.map(e, stackTrace);
    }
  }

  @override
  Future<int> getUnreadCount() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return 0;

      final res = await _supabase
          .from(SupabaseTables.notifications)
          .select('id')
          .eq('user_id', user.id)
          .eq('is_read', false);

      return (res as List).length;
    } catch (e, stackTrace) {
      throw SupabaseExceptionMapper.map(e, stackTrace);
    }
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    try {
      await _supabase.rpc(
        SupabaseTables.rpcMarkNotificationRead,
        params: {'p_notification_id': notificationId},
      );
    } catch (e, stackTrace) {
      throw SupabaseExceptionMapper.map(e, stackTrace);
    }
  }

  @override
  Future<void> markAllAsRead() async {
    try {
      await _supabase.rpc(SupabaseTables.rpcMarkAllNotificationsRead);
    } catch (e, stackTrace) {
      throw SupabaseExceptionMapper.map(e, stackTrace);
    }
  }
}

final notificationsRepositoryProvider = Provider<INotificationsRepository>((
  ref,
) {
  final supabase = ref.watch(supabaseClientProvider);
  return SupabaseNotificationsRepository(supabase);
});

final notificationsListProvider = FutureProvider<List<NotificationItem>>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final repo = ref.watch(notificationsRepositoryProvider);
  return repo.getNotifications();
});

final unreadNotificationsCountProvider = FutureProvider<int>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return 0;
  final repo = ref.watch(notificationsRepositoryProvider);
  return repo.getUnreadCount();
});
