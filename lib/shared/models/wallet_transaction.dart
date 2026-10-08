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
  final String? referenceId;

  bool get isCredit => type == WalletTransactionType.credit;

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] as String? ?? 'credit').toLowerCase();
    return WalletTransaction(
      id: json['id'] as String,
      type: rawType == 'debit'
          ? WalletTransactionType.debit
          : WalletTransactionType.credit,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      balanceAfter:
          (json['closing_balance'] as num?)?.toDouble() ??
          (json['balance_after'] as num?)?.toDouble() ??
          0.0,
      description: json['description'] as String? ?? 'Wallet Transaction',
      createdAt: DateTime.parse(json['created_at'] as String),
      referenceId: json['reference_id'] as String?,
    );
  }
}
