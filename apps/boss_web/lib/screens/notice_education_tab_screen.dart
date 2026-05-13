import 'package:flutter/material.dart';
import 'notice_list_screen.dart';
import 'education/education_list_screen.dart';
import 'tasks/alba_message_list_screen.dart';
import 'tasks/alba_expiration_list_screen.dart';

class NoticeEducationTabScreen extends StatelessWidget {
  const NoticeEducationTabScreen({
    super.key,
    required this.storeId,
    required this.workerId,
    required this.workerName,
    this.initialIndex = 0,
  });

  final String storeId;
  final String workerId;
  final String workerName;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      initialIndex: initialIndex,
      child: Column(
        children: [
          const Material(
            color: Colors.white,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: '공지사항'),
                Tab(text: '전달사항'),
                Tab(text: '유통기한'),
                Tab(text: '교육 및 매뉴얼'),
              ],
              indicatorColor: Colors.black,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.grey,
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                NoticeListScreen(
                  storeId: storeId,
                  workerId: workerId,
                  workerName: workerName,
                  showAppBar: false,
                ),
                AlbaMessageListScreen(
                  storeId: storeId,
                  workerName: workerName,
                  showAppBar: false,
                ),
                AlbaExpirationListScreen(
                  storeId: storeId,
                  showAppBar: false,
                ),
                EducationListScreen(
                  showAppBar: false,
                  storeId: storeId,
                  workerId: workerId,
                  workerName: workerName,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
