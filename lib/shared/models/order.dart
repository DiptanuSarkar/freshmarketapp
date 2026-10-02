enum OrderStatus {
  orderPlaced('Order Placed'),
  confirmed('Order Confirmed'),
  preparing('Preparing in Butchery'),
  packed('Quality Checked & Packed'),
  outForDelivery('Out for Delivery'),
  delivered('Delivered Fresh'),
  cancelled('Cancelled');

  const OrderStatus(this.displayName);
  final String displayName;
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
    required this.deliveryAddress,
    required this.deliverySlot,
    required this.createdAt,
    this.estimatedDeliveryTime,
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
  final String deliveryAddress;
  final String deliverySlot;
  final DateTime createdAt;
  final String? estimatedDeliveryTime;
}
