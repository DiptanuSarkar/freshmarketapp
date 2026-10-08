class CheckoutQuoteItem {
  const CheckoutQuoteItem({
    required this.cartItemId,
    required this.variantId,
    required this.productId,
    required this.productName,
    required this.variantTitle,
    required this.sku,
    required this.weight,
    required this.unitPrice,
    required this.originalPrice,
    required this.quantity,
    required this.totalPrice,
    required this.imageUrl,
    required this.availableStock,
    required this.isStockAvailable,
  });

  final String cartItemId;
  final String variantId;
  final String productId;
  final String productName;
  final String variantTitle;
  final String sku;
  final String weight;
  final double unitPrice;
  final double originalPrice;
  final int quantity;
  final double totalPrice;
  final String imageUrl;
  final int availableStock;
  final bool isStockAvailable;

  factory CheckoutQuoteItem.fromJson(Map<String, dynamic> json) {
    return CheckoutQuoteItem(
      cartItemId: json['cart_item_id'] as String? ?? '',
      variantId: json['variant_id'] as String? ?? '',
      productId: json['product_id'] as String? ?? '',
      productName: json['product_name'] as String? ?? '',
      variantTitle: json['variant_title'] as String? ?? '',
      sku: json['sku'] as String? ?? '',
      weight: json['weight'] as String? ?? '',
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      originalPrice: (json['original_price'] as num?)?.toDouble() ?? 0.0,
      quantity: json['quantity'] as int? ?? 1,
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0.0,
      imageUrl: json['image_url'] as String? ?? '',
      availableStock: json['available_stock'] as int? ?? 0,
      isStockAvailable: json['is_stock_available'] as bool? ?? true,
    );
  }
}

class CheckoutQuote {
  const CheckoutQuote({
    required this.cartId,
    required this.items,
    required this.itemCount,
    required this.subtotal,
    required this.itemDiscount,
    required this.couponDiscount,
    this.couponCode,
    required this.couponApplied,
    this.couponMessage,
    required this.deliveryFee,
    required this.platformFee,
    required this.taxAmount,
    required this.walletAmount,
    required this.grandTotal,
    required this.codPayableTotal,
    required this.stockValid,
    required this.serviceable,
    this.serviceAreaName,
    required this.minOrderForFreeDelivery,
    this.addressId,
    this.deliverySlotId,
    required this.slotValid,
  });

  final String cartId;
  final List<CheckoutQuoteItem> items;
  final int itemCount;
  final double subtotal;
  final double itemDiscount;
  final double couponDiscount;
  final String? couponCode;
  final bool couponApplied;
  final String? couponMessage;
  final double deliveryFee;
  final double platformFee;
  final double taxAmount;
  final double walletAmount;
  final double grandTotal;
  final double codPayableTotal;
  final bool stockValid;
  final bool serviceable;
  final String? serviceAreaName;
  final double minOrderForFreeDelivery;
  final String? addressId;
  final String? deliverySlotId;
  final bool slotValid;

  factory CheckoutQuote.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    final itemsList = rawItems
        .map((e) => CheckoutQuoteItem.fromJson(e as Map<String, dynamic>))
        .toList();

    return CheckoutQuote(
      cartId: json['cart_id'] as String? ?? '',
      items: itemsList,
      itemCount: json['item_count'] as int? ?? 0,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      itemDiscount: (json['item_discount'] as num?)?.toDouble() ?? 0.0,
      couponDiscount: (json['coupon_discount'] as num?)?.toDouble() ?? 0.0,
      couponCode: json['coupon_code'] as String?,
      couponApplied: json['coupon_applied'] as bool? ?? false,
      couponMessage: json['coupon_message'] as String?,
      deliveryFee: (json['delivery_fee'] as num?)?.toDouble() ?? 0.0,
      platformFee: (json['platform_fee'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0.0,
      walletAmount: (json['wallet_amount'] as num?)?.toDouble() ?? 0.0,
      grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0.0,
      codPayableTotal:
          ((json['cod_payable_total'] ?? json['cod_payable']) as num?)
              ?.toDouble() ??
          0.0,
      stockValid: json['stock_valid'] as bool? ?? true,
      serviceable: json['serviceable'] as bool? ?? false,
      serviceAreaName: json['service_area_name'] as String?,
      minOrderForFreeDelivery:
          (json['min_order_for_free_delivery'] as num?)?.toDouble() ?? 499.0,
      addressId: json['address_id'] as String?,
      deliverySlotId: json['delivery_slot_id'] as String?,
      slotValid: json['slot_valid'] as bool? ?? false,
    );
  }
}
