import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../shared/data/mock_data.dart';
import '../../../shared/models/category.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = MockData.categories;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('All Categories'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => context.push(AppRoutes.search),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppDimensions.lg),
        itemCount: categories.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: AppDimensions.md),
        itemBuilder: (context, index) {
          final cat = categories[index];
          return _buildCategoryCard(context, cat);
        },
      ),
    );
  }

  Widget _buildCategoryCard(BuildContext context, Category category) {
    return InkWell(
      onTap: () =>
          context.push('${AppRoutes.productListPrefix}/${category.slug}'),
      borderRadius: AppDimensions.roundedMd,
      child: Container(
        height: 104,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppDimensions.roundedMd,
          border: Border.all(color: AppColors.surfaceBorder, width: 1),
          boxShadow: AppDimensions.cardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // Left Image
            SizedBox(
              width: 104,
              height: 104,
              child: CachedNetworkImage(
                imageUrl: category.imageUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    Container(color: AppColors.surfaceSubtle),
                errorWidget: (context, url, error) => const Center(
                  child: Icon(Icons.restaurant, color: AppColors.textTertiary),
                ),
              ),
            ),

            // Middle Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppDimensions.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Text(
                          category.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (category.badge != null) ...[
                          const SizedBox(width: AppDimensions.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: const BoxDecoration(
                              color: AppColors.primaryContainer,
                              borderRadius: AppDimensions.roundedPill,
                            ),
                            child: Text(
                              category.badge!,
                              style: const TextStyle(
                                color: AppColors.primaryDark,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      category.description ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${category.itemCount} Fresh Items',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Right Arrow
            const Padding(
              padding: EdgeInsets.only(right: AppDimensions.md),
              child: Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
