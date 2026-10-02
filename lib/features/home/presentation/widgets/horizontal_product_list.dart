import 'package:flutter/material.dart';

import '../../../../core/constants/app_dimensions.dart';
import '../../../../shared/models/product.dart';
import '../../../product/presentation/widgets/product_card.dart';

class HorizontalProductList extends StatelessWidget {
  const HorizontalProductList({
    super.key,
    required this.products,
    this.height = 246.0,
    this.cardWidth = 164.0,
  });

  final List<Product> products;
  final double height;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: height,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.lg),
        scrollDirection: Axis.horizontal,
        itemCount: products.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AppDimensions.md),
        itemBuilder: (context, index) {
          final product = products[index];
          return ProductCard(product: product, width: cardWidth);
        },
      ),
    );
  }
}
