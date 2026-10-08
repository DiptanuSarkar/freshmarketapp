import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_routes.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../shared/models/category.dart';
import '../../../catalog/data/catalog_repository.dart';

class CategoryChipsSection extends ConsumerWidget {
  const CategoryChipsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(catalogCategoriesProvider);

    return categoriesAsync.when(
      loading: () => const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (categories) {
        if (categories.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppDimensions.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Explore by Category',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  InkWell(
                    onTap: () => context.push(AppRoutes.categories),
                    child: const Text(
                      'View All',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.md),
            SizedBox(
              height: 100,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.lg,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: AppDimensions.md),
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  return _buildCategoryItem(context, cat);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCategoryItem(BuildContext context, Category cat) {
    return InkWell(
      onTap: () => context.push('${AppRoutes.productListPrefix}/${cat.slug}'),
      borderRadius: AppDimensions.roundedMd,
      child: SizedBox(
        width: 76,
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primaryLight.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                boxShadow: AppDimensions.cardShadow,
              ),
              child: ClipOval(
                child: cat.imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: cat.imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            Container(color: AppColors.surfaceSubtle),
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(
                            Icons.restaurant,
                            color: AppColors.primary,
                            size: 24,
                          ),
                        ),
                      )
                    : Container(color: AppColors.surfaceSubtle),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              cat.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
