class Category {
  const Category({
    required this.id,
    required this.slug,
    required this.name,
    required this.imageUrl,
    this.itemCount = 0,
    this.badge,
    this.description,
  });

  final String id;
  final String slug;
  final String name;
  final String imageUrl;
  final int itemCount;
  final String? badge;
  final String? description;

  factory Category.fromJson(Map<String, dynamic> json, {int itemCount = 0}) {
    return Category(
      id: json['id'] as String,
      slug: json['slug'] as String,
      name: json['name'] as String,
      imageUrl: json['image_url'] as String? ?? '',
      badge: json['badge'] as String?,
      description: json['description'] as String?,
      itemCount: itemCount,
    );
  }
}
