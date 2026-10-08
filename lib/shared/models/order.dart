enum OrderStatus {
  paymentPending('Awaiting Payment'),
  orderPlaced('Order Placed'),
  confirmed('Confirmed'),
  preparing('Preparing in Butchery'),
  packed('Quality Checked & Packed'),
  outForDelivery('Out for Delivery'),
  delivered('Delivered Fresh'),
  cancelled('Cancelled');

  const OrderStatus(this.displayName);
  final String displayName;
  String get displayLabel => displayName;

  static OrderStatus fromDb(String raw) {
    switch (raw.toLowerCase().trim()) {
      case 'payment_pending':
      case 'paymentpending':
        return OrderStatus.paymentPending;
      case 'placed':
        return OrderStatus.orderPlaced;
      case 'pending':
        return OrderStatus.orderPlaced;
      case 'confirmed':
        return OrderStatus.confirmed;
      case 'preparing':
      case 'processing':
        return OrderStatus.preparing;
      case 'packed':
        return OrderStatus.packed;
      case 'out_for_delivery':
      case 'outfordelivery':
        return OrderStatus.outForDelivery;
      case 'delivered':
        return OrderStatus.delivered;
      case 'cancelled':
        return OrderStatus.cancelled;
      default:
        return OrderStatus.orderPlaced;
    }
  }

  static OrderStatus fromDbValue(String raw) => fromDb(raw);
}

class OrderItem {
  const OrderItem({
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.variantTitle,
    required this.unitPrice,
    required this.quantity,
    required this.imageUrl,
  });

  final String productId;
  final String variantId;
  final String productName;
  final String variantTitle;
  final double unitPrice;
  final int quantity;
  final String imageUrl;

  double get totalPrice => unitPrice * quantity;

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    String img =
        'https://images.unsplash.com/photo-1587593810167-a84920ea0781?auto=format&fit=crop&w=400&q=80';
    if (json['variant'] != null && json['variant']['products'] != null) {
      final imgs = json['variant']['products']['product_images'] as List?;
      if (imgs != null && imgs.isNotEmpty) {
        img = imgs.first['image_url'] as String? ?? img;
      }
    }
    return OrderItem(
      productId: json['variant']?['product_id'] as String? ?? '',
      variantId: json['variant_id'] as String? ?? '',
      productName: json['product_name'] as String? ?? 'Item',
      variantTitle: json['variant_name'] as String? ?? 'Standard',
      unitPrice: (json['price'] as num?)?.toDouble() ?? 0.0,
      quantity: json['quantity'] as int? ?? 1,
      imageUrl: img,
    );
  }
}

class OrderStatusHistoryItem {
  const OrderStatusHistoryItem({
    required this.id,
    required this.status,
    this.notes,
    required this.createdAt,
  });

  final String id;
  final OrderStatus status;
  final String? notes;
  final DateTime createdAt;

  factory OrderStatusHistoryItem.fromJson(Map<String, dynamic> json) {
    return OrderStatusHistoryItem(
      id: json['id'] as String,
      status: OrderStatus.fromDb(json['status'] as String? ?? 'placed'),
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class CustomerOrder {
  const CustomerOrder({
    required this.id,
    required this.orderNumber,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.deliveryFee,
    required this.totalAmount,
    required this.status,
    required this.paymentMethod,
    this.paymentStatus = 'PENDING',
    required this.deliveryAddress,
    required this.deliverySlot,
    required this.createdAt,
    this.estimatedDeliveryTime,
    this.cancellationReason,
    this.cancelledAt,
    this.statusHistory = const [],
  });

  final String id;
  final String orderNumber;
  final List<OrderItem> items;
  final double subtotal;
  final double discount;
  final double deliveryFee;
  final double totalAmount;
  final OrderStatus status;
  final String paymentMethod;
  final String paymentStatus;
  final String deliveryAddress;
  final String deliverySlot;
  final DateTime createdAt;
  final String? estimatedDeliveryTime;
  final String? cancellationReason;
  final DateTime? cancelledAt;
  final List<OrderStatusHistoryItem> statusHistory;

  bool get isPaymentPending => status == OrderStatus.paymentPending;
  bool get canCancelPayment => status == OrderStatus.paymentPending;

  factory CustomerOrder.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'] as String? ?? 'pending';
    final parsedStatus = OrderStatus.fromDb(rawStatus);

    // Items
    final itemsList = <OrderItem>[];
    if (json['order_items'] != null && json['order_items'] is List) {
      for (final rawItem in json['order_items'] as List) {
        itemsList.add(OrderItem.fromJson(rawItem as Map<String, dynamic>));
      }
    }

    // Status History
    final historyList = <OrderStatusHistoryItem>[];
    if (json['order_status_history'] != null &&
        json['order_status_history'] is List) {
      for (final rawHistory in json['order_status_history'] as List) {
        historyList.add(
          OrderStatusHistoryItem.fromJson(rawHistory as Map<String, dynamic>),
        );
      }
      historyList.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    // Payment Status from payments relation
    String payStatus = 'PENDING';
    if (json['payments'] != null &&
        json['payments'] is List &&
        (json['payments'] as List).isNotEmpty) {
      final p = (json['payments'] as List).first as Map<String, dynamic>;
      payStatus = (p['status'] as String? ?? 'pending').toUpperCase();
    }

    // Address display from snapshot
    String addressStr = 'Saved Address';
    if (json['delivery_address_snapshot'] != null &&
        json['delivery_address_snapshot'] is Map) {
      final snap = json['delivery_address_snapshot'] as Map<String, dynamic>;
      final line1 = snap['address_line1'] as String? ?? '';
      final line2 = snap['address_line2'] as String? ?? '';
      final city = snap['city'] as String? ?? '';
      final pin = snap['pincode'] as String? ?? '';
      addressStr = [
        line1,
        if (line2.isNotEmpty) line2,
        '$city - $pin',
      ].join(', ');
    }

    // Slot display from snapshot
    String slotStr = 'Standard Delivery';
    if (json['delivery_slot_snapshot'] != null &&
        json['delivery_slot_snapshot'] is Map) {
      final snap = json['delivery_slot_snapshot'] as Map<String, dynamic>;
      slotStr = snap['name'] as String? ?? slotStr;
    }

    return CustomerOrder(
      id: json['id'] as String,
      orderNumber: json['order_number'] as String? ?? 'FM-UNKNOWN',
      items: itemsList,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      discount:
          ((json['discount'] ?? json['coupon_discount']) as num?)?.toDouble() ??
          0.0,
      deliveryFee: (json['delivery_fee'] as num?)?.toDouble() ?? 0.0,
      totalAmount:
          ((json['total'] ?? json['grand_total']) as num?)?.toDouble() ?? 0.0,
      status: parsedStatus,
      paymentMethod: (json['payment_method'] as String? ?? 'COD').toUpperCase(),
      paymentStatus: payStatus,
      deliveryAddress: addressStr,
      deliverySlot: slotStr,
      createdAt: DateTime.parse(json['created_at'] as String),
      estimatedDeliveryTime: 'Today within 120 mins',
      cancellationReason: json['cancellation_reason'] as String?,
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.tryParse(json['cancelled_at'] as String)
          : null,
      statusHistory: historyList,
    );
  }
}
