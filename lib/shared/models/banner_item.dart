class BannerItem {
  const BannerItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.badgeText,
    this.targetCategorySlug,
    this.actionLabel = 'Shop Now',
  });

  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String badgeText;
  final String? targetCategorySlug;
  final String actionLabel;
}
