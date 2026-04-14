void main() {
  final d = DateTime.now();
  final dString = d.toIso8601String();
  print('Date: $dString');
  final dParsed = DateTime.tryParse(dString);
  print('Parsed: $dParsed');
  
  final inH = int.tryParse('09') ?? 9;
  final inDt = DateTime(d.year, d.month, d.day, inH, 0);
  final str = inDt.toIso8601String();
  print('inDt string: $str');
  final parsedInDt = DateTime.tryParse(str);
  print('parsedInDt is local? ${!parsedInDt!.isUtc}');

  final startDay = d.subtract(Duration(days: 40));
  for (int i = 0; i <= 1; i++) {
    final d2 = startDay.add(Duration(days: i));
    final inDt2 = DateTime(d2.year, d2.month, d2.day, 9, 0);
    print('Generated: ${inDt2.toIso8601String()}');
  }
}
