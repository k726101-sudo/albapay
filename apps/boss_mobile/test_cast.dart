void main() {
  final List<Map<String, Object>> dummyWorkers = [
    {'id': 'worker_a', 'hours': 8, 'workDays': [1,2,3]}
  ];
  
  try {
    generate(workersData: dummyWorkers);
    print('SUCCESS');
  } catch (e) {
    print('ERROR: \$e');
  }
}

void generate({required List<Map<String, dynamic>> workersData}) {
  print(workersData.length);
}
