void main() {
  final createdAtStr = "2026-05-02T18:35:23.123456";
  final dt = DateTime.parse(createdAtStr);
  final str2 = dt.toIso8601String();
  print("Orig: " + createdAtStr);
  print("New : " + str2);
  print("Match? " + (createdAtStr == str2).toString());
}
