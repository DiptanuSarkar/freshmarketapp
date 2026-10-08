/// Centralized database table names and RPC names for Supabase Data API calls.
abstract final class SupabaseTables {
  static const String profiles = 'profiles';
  static const String categories = 'categories';
  static const String products = 'products';
  static const String productVariants = 'product_variants';
  static const String productImages = 'product_images';
  static const String inventory = 'inventory';
  static const String productReviews = 'product_reviews';
  static const String banners = 'banners';
  static const String homeSections = 'home_sections';
  static const String homeSectionItems = 'home_section_items';
  static const String serviceAreas = 'service_areas';
  static const String deliverySlots = 'delivery_slots';
  static const String addresses = 'addresses';
  static const String carts = 'carts';
  static const String cartItems = 'cart_items';
  static const String coupons = 'coupons';
  static const String couponUsers = 'coupon_users';
  static const String couponCategories = 'coupon_categories';
  static const String wishlistItems = 'wishlist_items';
  static const String orders = 'orders';
  static const String orderItems = 'order_items';
  static const String orderStatusHistory = 'order_status_history';
  static const String payments = 'payments';
  static const String refunds = 'refunds';
  static const String walletAccounts = 'wallet_accounts';
  static const String walletTransactions = 'wallet_transactions';
  static const String notifications = 'notifications';
  static const String contactMessages = 'contact_messages';
  static const String appSettings = 'app_settings';

  // RPCs
  static const String rpcMarkNotificationRead = 'mark_notification_as_read';
  static const String rpcMarkAllNotificationsRead =
      'mark_all_notifications_as_read';
}
