import '../models/address.dart';
import '../models/banner_item.dart';
import '../models/category.dart';
import '../models/notification_item.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/product_variant.dart';
import '../models/wallet_transaction.dart';

/// Isolated mock presentation data store.
/// In future sessions, this will be replaced with Supabase repositories.
abstract final class MockData {
  // Categories
  static const List<Category> categories = [
    Category(
      id: 'cat_chicken',
      slug: 'chicken',
      name: 'Chicken',
      imageUrl: 'https://images.unsplash.com/photo-1587593810167-a84920ea0781?auto=format&fit=crop&w=400&q=80',
      itemCount: 18,
      badge: 'Farm Fresh',
      description: 'Antibiotic residue-free, tender farm-raised chicken cut fresh daily.',
    ),
    Category(
      id: 'cat_mutton',
      slug: 'mutton',
      name: 'Mutton',
      imageUrl: 'https://images.unsplash.com/photo-1603048588665-791ca8aea617?auto=format&fit=crop&w=400&q=80',
      itemCount: 12,
      badge: 'Grass Fed',
      description: 'Prime pasture-raised rich goat and lamb cuts, trimmed to perfection.',
    ),
    Category(
      id: 'cat_fish',
      slug: 'fish',
      name: 'Fish & Seafood',
      imageUrl: 'https://images.unsplash.com/photo-1534939561126-855b8675edd7?auto=format&fit=crop&w=400&q=80',
      itemCount: 24,
      badge: 'Daily Catch',
      description:
          'Fresh coastal catch from day-boats, cleaned and descaled with care.',
    ),
    Category(
      id: 'cat_pork',
      slug: 'pork',
      name: 'Pork',
      imageUrl: 'https://images.unsplash.com/photo-1602498456745-e9503b30470b?auto=format&fit=crop&w=400&q=80',
      itemCount: 8,
      badge: 'Premium',
      description:
          'Hygienically sourced tender pork chops, belly cuts, and ribs.',
    ),
    Category(
      id: 'cat_grocery',
      slug: 'grocery',
      name: 'Grocery & Spices',
      imageUrl: 'https://images.unsplash.com/photo-1596040033229-a9821ebd058d?auto=format&fit=crop&w=400&q=80',
      itemCount: 35,
      badge: 'Kitchen Staples',
      description:
          'Pure cooking oils, artisanal ground spices, eggs, and marinades.',
    ),
  ];

  // Banners
  static const List<BannerItem> banners = [
    BannerItem(
      id: 'b1',
      title: 'Weekend Barbeque Special',
      subtitle: 'Flat 20% OFF on Prime Mutton & Chicken Cuts',
      imageUrl: 'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=800&q=80',
      badgeText: 'LIMITED OFFER',
      targetCategorySlug: 'chicken',
    ),
    BannerItem(
      id: 'b2',
      title: 'Fresh Catch of the Morning',
      subtitle: 'Direct from harbor to your kitchen within 120 mins',
      imageUrl: 'https://images.unsplash.com/photo-1519708227418-c8fd9a32b7a2?auto=format&fit=crop&w=800&q=80',
      badgeText: 'FRESH ARRIVAL',
      targetCategorySlug: 'fish',
    ),
    BannerItem(
      id: 'b3',
      title: 'Artisanal Marinades & Spices',
      subtitle: 'Free fresh eggs pack on orders above ₹499',
      imageUrl: 'https://images.unsplash.com/photo-1506368249639-73a05d6f6488?auto=format&fit=crop&w=800&q=80',
      badgeText: 'FREE GIFT',
      targetCategorySlug: 'grocery',
    ),
  ];

  // Products (Unified variant model)
  static const List<Product> products = [
    // 1. Chicken Curry Cut (Variable)
    Product(
      id: 'prod_chk_curry',
      name: 'Fresh Farm Chicken Curry Cut (Skinless)',
      categorySlug: 'chicken',
      shortDescription:
          'Tender antibiotic-free chicken mix of bone-in and boneless pieces.',
      description: 'Our signature chicken curry cut includes equal portions of drumsticks, thigh cuts, wings, and tender breast meat. Sourced directly from biosecure partner farms and temperature-controlled from processing to doorstep.',
      images: [
        'https://images.unsplash.com/photo-1587593810167-a84920ea0781?auto=format&fit=crop&w=600&q=80',
        'https://images.unsplash.com/photo-1604503468506-a8da13d82791?auto=format&fit=crop&w=600&q=80',
      ],
      isFeatured: true,
      isDailyDeal: true,
      isPopular: true,
      rating: 4.8,
      reviewCount: 342,
      pieces: '12-16 Pieces',
      servings: 'Serves 3-4',
      variants: [
        ProductVariant(
          id: 'var_chk_curry_500g',
          sku: 'CHK-CURRY-500G',
          title: '500 g',
          weightInGrams: 500,
          price: 159.0,
          originalPrice: 189.0,
          stockQuantity: 45,
          netWeightDisplay: 'Net: 470g | Gross: 500g',
        ),
        ProductVariant(
          id: 'var_chk_curry_1000g',
          sku: 'CHK-CURRY-1000G',
          title: '1 kg',
          weightInGrams: 1000,
          price: 299.0,
          originalPrice: 359.0,
          stockQuantity: 30,
          netWeightDisplay: 'Net: 950g | Gross: 1000g',
        ),
        ProductVariant(
          id: 'var_chk_curry_2000g',
          sku: 'CHK-CURRY-2000G',
          title: '2 kg (Family Pack)',
          weightInGrams: 2000,
          price: 579.0,
          originalPrice: 699.0,
          stockQuantity: 15,
          netWeightDisplay: 'Net: 1900g | Gross: 2000g',
        ),
      ],
    ),

    // 2. Chicken Boneless Breast (Variable)
    Product(
      id: 'prod_chk_breast',
      name: 'Chicken Breast Fillet (Boneless)',
      categorySlug: 'chicken',
      shortDescription: 'High-protein, lean tender boneless chicken fillets.',
      description: 'Perfect for grilling, pan-searing, meal prep, and salads. Expertly trimmed with zero excess fat. 100% natural, antibiotic and hormone free.',
      images: [
        'https://images.unsplash.com/photo-1604503468506-a8da13d82791?auto=format&fit=crop&w=600&q=80',
        'https://images.unsplash.com/photo-1587593810167-a84920ea0781?auto=format&fit=crop&w=600&q=80',
      ],
      isFeatured: true,
      isDailyDeal: false,
      isPopular: true,
      rating: 4.9,
      reviewCount: 280,
      pieces: '4-6 Fillets',
      servings: 'Serves 2-3',
      variants: [
        ProductVariant(
          id: 'var_chk_brst_500g',
          sku: 'CHK-BRST-500G',
          title: '500 g',
          weightInGrams: 500,
          price: 239.0,
          originalPrice: 279.0,
          stockQuantity: 40,
          netWeightDisplay: 'Net: 500g (Boneless)',
        ),
        ProductVariant(
          id: 'var_chk_brst_1000g',
          sku: 'CHK-BRST-1000G',
          title: '1 kg',
          weightInGrams: 1000,
          price: 459.0,
          originalPrice: 539.0,
          stockQuantity: 20,
          netWeightDisplay: 'Net: 1000g (Boneless)',
        ),
      ],
    ),

    // 3. Premium Goat Curry Cut (Variable)
    Product(
      id: 'prod_mut_curry',
      name: 'Rich Goat Curry Cut (Fresh Mutton)',
      categorySlug: 'mutton',
      shortDescription: 'Tender grass-fed goat meat cuts rich in flavour.',
      description: 'Carefully hand-curated pieces from the shoulder, ribs, and leg for authentic rich gravies and biryanis. Thoroughly washed and packed hygienically.',
      images: [
        'https://images.unsplash.com/photo-1603048588665-791ca8aea617?auto=format&fit=crop&w=600&q=80',
      ],
      isFeatured: true,
      isDailyDeal: true,
      isPopular: true,
      rating: 4.7,
      reviewCount: 195,
      pieces: '12-14 Pieces',
      servings: 'Serves 3-4',
      variants: [
        ProductVariant(
          id: 'var_mut_curry_500g',
          sku: 'MUT-CURRY-500G',
          title: '500 g',
          weightInGrams: 500,
          price: 449.0,
          originalPrice: 499.0,
          stockQuantity: 25,
          netWeightDisplay: 'Net: 480g | Gross: 500g',
        ),
        ProductVariant(
          id: 'var_mut_curry_1000g',
          sku: 'MUT-CURRY-1000G',
          title: '1 kg',
          weightInGrams: 1000,
          price: 879.0,
          originalPrice: 979.0,
          stockQuantity: 18,
          netWeightDisplay: 'Net: 960g | Gross: 1000g',
        ),
      ],
    ),

    // 4. Seer Fish / Surmai Steaks (Variable)
    Product(
      id: 'prod_fish_seer',
      name: 'Fresh Seer Fish / Surmai Steaks',
      categorySlug: 'fish',
      shortDescription:
          'Fresh ocean catch sliced into neat juicy round steaks.',
      description: 'Seer fish is the king of coastal fish, acclaimed for its firm white meat and rich omega-3 profile. Descaled and sliced into uniform steaks ready for pan-fry or fish curry.',
      images: [
        'https://images.unsplash.com/photo-1534939561126-855b8675edd7?auto=format&fit=crop&w=600&q=80',
      ],
      isFeatured: true,
      isDailyDeal: false,
      isPopular: true,
      rating: 4.9,
      reviewCount: 160,
      pieces: '4-6 Steaks',
      servings: 'Serves 2-3',
      variants: [
        ProductVariant(
          id: 'var_fish_seer_500g',
          sku: 'FISH-SEER-500G',
          title: '500 g',
          weightInGrams: 500,
          price: 549.0,
          originalPrice: 620.0,
          stockQuantity: 15,
          netWeightDisplay: 'Net: 450g | Descaled & Cleaned',
        ),
        ProductVariant(
          id: 'var_fish_seer_1000g',
          sku: 'FISH-SEER-1000G',
          title: '1 kg',
          weightInGrams: 1000,
          price: 1049.0,
          originalPrice: 1199.0,
          stockQuantity: 10,
          netWeightDisplay: 'Net: 900g | Cleaned Steaks',
        ),
      ],
    ),

    // 5. Pork Chops (Variable)
    Product(
      id: 'prod_pork_chops',
      name: 'Fresh Pork Chops (Bone-in)',
      categorySlug: 'pork',
      shortDescription: 'Succulent center-cut pork chops with gentle marbling.',
      description: 'Sourced from certified biosecure farms. Tender, flavourful, and ideal for roasting, grilling, or barbecues with your favourite marinades.',
      images: [
        'https://images.unsplash.com/photo-1602498456745-e9503b30470b?auto=format&fit=crop&w=600&q=80',
      ],
      isFeatured: false,
      isDailyDeal: true,
      isPopular: false,
      rating: 4.6,
      reviewCount: 88,
      pieces: '4-5 Chops',
      servings: 'Serves 2-3',
      variants: [
        ProductVariant(
          id: 'var_pork_chop_500g',
          sku: 'PRK-CHOP-500G',
          title: '500 g',
          weightInGrams: 500,
          price: 329.0,
          originalPrice: 380.0,
          stockQuantity: 20,
          netWeightDisplay: 'Net: 500g',
        ),
        ProductVariant(
          id: 'var_pork_chop_1000g',
          sku: 'PRK-CHOP-1000G',
          title: '1 kg',
          weightInGrams: 1000,
          price: 629.0,
          originalPrice: 720.0,
          stockQuantity: 12,
          netWeightDisplay: 'Net: 1000g',
        ),
      ],
    ),

    // 6. Farm Fresh White Eggs (Simple product with single default variant)
    Product(
      id: 'prod_groc_eggs',
      name: 'Farm Fresh Classic White Eggs (Pack of 12)',
      categorySlug: 'grocery',
      shortDescription:
          'Naturally laid, washed, and sanitized high-protein eggs.',
      description: 'Graded for freshness and size. Rich in essential vitamins and pure protein, delivered intact in secure shock-absorbent eco-packaging.',
      images: [
        'https://images.unsplash.com/photo-1582722872445-44dc5f7e3c8f?auto=format&fit=crop&w=600&q=80',
      ],
      isFeatured: false,
      isDailyDeal: false,
      isPopular: true,
      rating: 4.9,
      reviewCount: 512,
      pieces: '12 Eggs',
      servings: 'Breakfast Essentials',
      variants: [
        ProductVariant(
          id: 'var_groc_eggs_12',
          sku: 'GROC-EGGS-12PK',
          title: '12 pcs Pack',
          weightInGrams: 600,
          price: 99.0,
          originalPrice: 120.0,
          stockQuantity: 80,
          netWeightDisplay: '12 sanitized eggs',
        ),
      ],
    ),

    // 7. Artisanal Meat Masala Powder (Simple Product)
    Product(
      id: 'prod_groc_masala',
      name: 'Artisanal Royal Meat Curry Masala',
      categorySlug: 'grocery',
      shortDescription:
          'Slow-roasted whole spice blend crafted for mutton and chicken.',
      description: 'Contains stone-ground Kashmiri chillies, star anise, green cardamom, roasted coriander, and mace. Zero artificial colours or preservatives.',
      images: [
        'https://images.unsplash.com/photo-1596040033229-a9821ebd058d?auto=format&fit=crop&w=600&q=80',
      ],
      isFeatured: false,
      isDailyDeal: false,
      isPopular: false,
      rating: 4.8,
      reviewCount: 76,
      pieces: '1 Pouch',
      servings: '100 g',
      variants: [
        ProductVariant(
          id: 'var_groc_masala_100g',
          sku: 'GROC-MASALA-100G',
          title: '100 g',
          weightInGrams: 100,
          price: 79.0,
          originalPrice: 95.0,
          stockQuantity: 60,
          netWeightDisplay: 'Net: 100g',
        ),
      ],
    ),
  ];

  // Saved Addresses
  static const List<UserAddress> addresses = [
    UserAddress(
      id: 'addr_1',
      tag: 'Home',
      recipientName: 'Rahul Sharma',
      phone: '+91 98765 43210',
      houseOrFlat: 'Flat 402, Green Glen Heights',
      streetOrArea: 'Outer Ring Road, Bellandur',
      landmark: 'Opposite Central Mall',
      city: 'Bengaluru',
      pincode: '560103',
      isDefault: true,
    ),
    UserAddress(
      id: 'addr_2',
      tag: 'Work',
      recipientName: 'Rahul Sharma',
      phone: '+91 98765 43210',
      houseOrFlat: 'Building 12B, Level 4, Tech Park',
      streetOrArea: 'Whitefield Main Road',
      landmark: 'Near Metro Station',
      city: 'Bengaluru',
      pincode: '560066',
      isDefault: false,
    ),
  ];

  // Customer Orders
  static final List<CustomerOrder> sampleOrders = [
    CustomerOrder(
      id: 'ord_1001',
      orderNumber: 'FM-2026-9041',
      items: const [
        OrderItem(
          productId: 'prod_chk_curry',
          variantId: 'var_chk_curry_1000g',
          productName: 'Fresh Farm Chicken Curry Cut (Skinless)',
          variantTitle: '1 kg',
          unitPrice: 299.0,
          quantity: 1,
          imageUrl: 'https://images.unsplash.com/photo-1587593810167-a84920ea0781?auto=format&fit=crop&w=200&q=80',
        ),
        OrderItem(
          productId: 'prod_groc_eggs',
          variantId: 'var_groc_eggs_12',
          productName: 'Farm Fresh Classic White Eggs (Pack of 12)',
          variantTitle: '12 pcs Pack',
          unitPrice: 99.0,
          quantity: 2,
          imageUrl: 'https://images.unsplash.com/photo-1582722872445-44dc5f7e3c8f?auto=format&fit=crop&w=200&q=80',
        ),
      ],
      subtotal: 497.0,
      discount: 40.0,
      deliveryFee: 0.0,
      totalAmount: 457.0,
      status: OrderStatus.outForDelivery,
      paymentMethod: 'Razorpay (UPI)',
      deliveryAddress:
          'Flat 402, Green Glen Heights, Bellandur, Bengaluru - 560103',
      deliverySlot: 'Today, 5:00 PM - 7:00 PM',
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      estimatedDeliveryTime: 'Arriving in ~25 mins',
    ),
    CustomerOrder(
      id: 'ord_1000',
      orderNumber: 'FM-2026-8812',
      items: const [
        OrderItem(
          productId: 'prod_mut_curry',
          variantId: 'var_mut_curry_500g',
          productName: 'Rich Goat Curry Cut (Fresh Mutton)',
          variantTitle: '500 g',
          unitPrice: 449.0,
          quantity: 1,
          imageUrl: 'https://images.unsplash.com/photo-1603048588665-791ca8aea617?auto=format&fit=crop&w=200&q=80',
        ),
      ],
      subtotal: 449.0,
      discount: 0.0,
      deliveryFee: 39.0,
      totalAmount: 488.0,
      status: OrderStatus.delivered,
      paymentMethod: 'Cash on Delivery',
      deliveryAddress:
          'Flat 402, Green Glen Heights, Bellandur, Bengaluru - 560103',
      deliverySlot: '26 Sep, 10:00 AM - 12:00 PM',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
  ];

  // Wallet Transactions (Ledger format)
  static final List<WalletTransaction> walletTransactions = [
    WalletTransaction(
      id: 'tx_3',
      type: WalletTransactionType.debit,
      amount: 40.0,
      balanceAfter: 210.0,
      description: 'Used for Order #FM-2026-9041',
      referenceId: 'ord_1001',
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    ),
    WalletTransaction(
      id: 'tx_2',
      type: WalletTransactionType.credit,
      amount: 150.0,
      balanceAfter: 250.0,
      description: 'Cashback reward for Weekend Special',
      referenceId: 'promo_reward_2026',
      createdAt: DateTime.now().subtract(const Duration(days: 4)),
    ),
    WalletTransaction(
      id: 'tx_1',
      type: WalletTransactionType.credit,
      amount: 100.0,
      balanceAfter: 100.0,
      description: 'Welcome bonus credited to wallet',
      referenceId: 'welcome_bonus',
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
    ),
  ];

  // Notifications
  static final List<NotificationItem> notifications = [
    NotificationItem(
      id: 'notif_1',
      title: 'Order Out for Delivery! 🛵',
      body: 'Your fresh meats order #FM-2026-9041 is on the way. Our delivery partner is keeping it chilled.',
      type: NotificationType.order,
      createdAt: DateTime.now().subtract(const Duration(minutes: 25)),
      actionRoute: '/orders/ord_1001',
    ),
    NotificationItem(
      id: 'notif_2',
      title: 'Weekend Seafood Carnival 🦐',
      body: 'Fresh Seer Fish, Tiger Prawns, and Crabs caught this morning. Enjoy flat 15% off!',
      type: NotificationType.offer,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      actionRoute: '/categories',
    ),
    NotificationItem(
      id: 'notif_3',
      title: 'Wallet Cashback Credited! 🎉',
      body: '₹150 has been added to your FreshMarket wallet for your recent order.',
      type: NotificationType.wallet,
      createdAt: DateTime.now().subtract(const Duration(days: 4)),
      actionRoute: '/wallet',
    ),
  ];
}
