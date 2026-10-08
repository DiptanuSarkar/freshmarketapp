class ContactMessage {
  const ContactMessage({
    required this.id,
    this.userId,
    required this.name,
    this.email,
    this.phone,
    this.subject,
    required this.message,
    this.status = 'new',
    required this.createdAt,
  });

  final String id;
  final String? userId;
  final String name;
  final String? email;
  final String? phone;
  final String? subject;
  final String message;
  final String status;
  final DateTime createdAt;

  factory ContactMessage.fromJson(Map<String, dynamic> json) {
    return ContactMessage(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      name: json['name'] as String,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      subject: json['subject'] as String?,
      message: json['message'] as String,
      status: json['status'] as String? ?? 'new',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
