void main() {
  List<int> intList = [1, 2, 3, 4];
  try {
    List<dynamic>? dynList = intList as List<dynamic>?;
    print('Cast success: $dynList');
  } catch (e) {
    print('Cast failed: $e');
  }
}
