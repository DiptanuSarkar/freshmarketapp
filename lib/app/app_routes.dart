/// Centralized navigation route names and paths.
abstract final class AppRoutes {
  // Splash & Onboarding
  static const String splash = '/';

  // Auth Routes
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';

  // Bottom Nav Shell Routes
  static const String home = '/home';
  static const String categories = '/categories';
  static const String cart = '/cart';
  static const String orders = '/orders';
  static const String account = '/account';

  // Catalog & Product Routes
  static const String search = '/search';
  static const String productList = '/products/:categorySlug';
  static const String productListPrefix = '/products';
  static const String productDetail = '/product/:id';
  static const String productDetailPrefix = '/product';

  // Shopping & Checkout
  static const String checkout = '/checkout';
  static const String paymentSuccess = '/payment-success';

  // Customer Management & Support
  static const String orderDetail = '/orders/:id';
  static const String orderDetailPrefix = '/orders';
  static const String wishlist = '/wishlist';
  static const String addresses = '/addresses';
  static const String addAddress = '/addresses/add';
  static const String wallet = '/wallet';
  static const String notifications = '/notifications';
  static const String aboutUs = '/about-us';
  static const String contactUs = '/contact-us';
}
