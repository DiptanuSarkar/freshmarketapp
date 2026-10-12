class WalletAccount {
  const WalletAccount({required this.balance, required this.reservedBalance});

  /// Total ledger balance of the account
  final double balance;

  /// Amount reserved for pending orders / mixed payments
  final double reservedBalance;

  /// Spendable balance available for new checkouts
  double get availableBalance =>
      (balance - reservedBalance).clamp(0.0, double.infinity);

  factory WalletAccount.fromJson(Map<String, dynamic> json) {
    return WalletAccount(
      balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
      reservedBalance: (json['reserved_balance'] as num?)?.toDouble() ?? 0.0,
    );
  }

  factory WalletAccount.zero() =>
      const WalletAccount(balance: 0.0, reservedBalance: 0.0);

  Map<String, dynamic> toJson() => {
    'balance': balance,
    'reserved_balance': reservedBalance,
    'available_balance': availableBalance,
  };
}
