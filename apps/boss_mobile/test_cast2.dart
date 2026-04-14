void main() {
  final Map<String, Object> map = {'workDays': [1,2,3,4]};
  try {
    final workDays = (map['workDays'] as List<dynamic>?)?.map((e) => e as int).toList() ?? [];
    print(workDays);
  } catch (e) {
    print('Failed: \$e');
  }
}
