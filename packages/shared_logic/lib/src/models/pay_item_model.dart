enum WageType { hourly, monthly }

class CustomPayItem {
  final String label;
  final int amount;

  const CustomPayItem({
    required this.label,
    required this.amount,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'amount': amount,
      };

  factory CustomPayItem.fromJson(Map<String, dynamic> json) {
    return CustomPayItem(
      label: json['label']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
    );
  }
}
