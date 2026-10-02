enum WalletTransactionType { credit, debit }

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.description,
    required this.createdAt,
    this.referenceId,
  });

  final String id;
  final WalletTransactionType type;
  final double amount;
  final double balanceAfter;
  final String description;
  final DateTime createdAt;
  final String? referenceId; // e.g. Order ID, Refund ID, Top-up transaction ID

  bool get isCredit => type == WalletTransactionType.credit;
}
