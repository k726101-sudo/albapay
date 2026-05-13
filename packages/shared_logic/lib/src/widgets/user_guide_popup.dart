import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum GuideType { boss, alba }

class GuidePageData {
  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;

  const GuidePageData({
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
  });
}

class UserGuidePopup extends StatefulWidget {
  final GuideType type;

  const UserGuidePopup({super.key, required this.type});

  static Future<void> showIfNeeded(BuildContext context, GuideType type) async {
    final prefs = await SharedPreferences.getInstance();
    final prefKey = type == GuideType.boss
        ? 'has_seen_boss_guide_v1'
        : 'has_seen_alba_guide_v1';
    final hasSeen = prefs.getBool(prefKey) ?? false;

    if (!hasSeen && context.mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => UserGuidePopup(type: type),
      );
      // Wait to set the flag inside the widget depending on 'Do not show again' checkbox
    }
  }

  @override
  State<UserGuidePopup> createState() => _UserGuidePopupState();
}

class _UserGuidePopupState extends State<UserGuidePopup> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _doNotShowAgain = false;

  late final List<GuidePageData> _pages;

  @override
  void initState() {
    super.initState();
    if (widget.type == GuideType.boss) {
      _pages = const [
        GuidePageData(
          title: '맞춤형 매장 세팅',
          description:
              '출퇴근 방식(GPS/QR), 정산 기준일, 휴게시간 등 우리 매장 환경에 맞춰 세밀하게 설정하세요.',
          icon: Icons.storefront_rounded,
          iconColor: Colors.blueAccent,
        ),
        GuidePageData(
          title: '초간편 직원 초대',
          description: '알바생의 기본 정보를 등록하고, 터치 한 번으로 카카오톡 초대 코드를 전송하세요.',
          icon: Icons.person_add_rounded,
          iconColor: Colors.purpleAccent,
        ),
        GuidePageData(
          title: '완벽한 노무 관리',
          description:
              '근로계약서, 필수 동의서 등 모든 노무 서류를 한 번에 자동 생성하고 스마트폰으로 간편하게 전자서명 받으세요.',
          icon: Icons.assignment_turned_in_rounded,
          iconColor: Colors.green,
        ),
        GuidePageData(
          title: '스마트 급여 정산',
          description:
              'GPS 기반 출퇴근 기록을 바탕으로 주휴/야간수당이 자동 계산된 정확한 급여를 실시간으로 확인하세요.',
          icon: Icons.calculate_rounded,
          iconColor: Colors.orangeAccent,
        ),
      ];
    } else {
      _pages = const [
        GuidePageData(
          title: '초대코드 입력',
          description: '사장님이 전달해주신 매장 전용 6자리 초대코드를 입력하면 즉시 우리 매장과 연결됩니다!',
          icon: Icons.vpn_key_rounded,
          iconColor: Colors.amber,
        ),
        GuidePageData(
          title: '간편 출퇴근 체크',
          description: '매장 안에서 스마트폰 GPS나 QR 코드를 이용해 1초 만에 빠르고 확실하게 출퇴근을 인증하세요.',
          icon: Icons.touch_app_rounded,
          iconColor: Colors.indigoAccent,
        ),
        GuidePageData(
          title: '동료 대근 지정',
          description:
              '피치 못할 사정이 생겼을 때, 앱을 통해 간편하게 나의 근무를 동료에게 양도하고 대근을 요청해보세요.',
          icon: Icons.swap_horizontal_circle_rounded,
          iconColor: Colors.teal,
        ),
        GuidePageData(
          title: '내 급여 실시간 조회',
          description:
              '이번 달 최신 예상 급여와 사장님이 발급해주신 온라인 근로계약서를 앱에서 언제든 열람할 수 있습니다.',
          icon: Icons.request_quote_rounded,
          iconColor: Colors.pinkAccent,
        ),
      ];
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _handleClose(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final prefKey = widget.type == GuideType.boss
        ? 'has_seen_boss_guide_v1'
        : 'has_seen_alba_guide_v1';

    // If they clicked "Do not show again", mark it. If not, also mark it?
    // Usually guides show once. Let's make "다시 보지 않기" strictly override, but regular dismiss also sets it so it doesn't pop up every start.
    // Actually, if we just want it to show once overall unless re-requested, we just set it to true.
    await prefs.setBool(prefKey, true);

    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.grey),
                onPressed: () => _handleClose(context),
              ),
            ),
            SizedBox(
              height: 280,
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(page.icon, size: 80, color: page.iconColor),
                        const SizedBox(height: 24),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page.description,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? const Color(0xFF1a1a2e)
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: FilledButton(
                onPressed: () {
                  if (_currentPage < _pages.length - 1) {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  } else {
                    _handleClose(context);
                  }
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF1a1a2e),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _currentPage < _pages.length - 1 ? '다음' : '시작하기',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Checkbox(
                  value: _doNotShowAgain,
                  onChanged: (v) =>
                      setState(() => _doNotShowAgain = v ?? false),
                  activeColor: const Color(0xFF1a1a2e),
                ),
                GestureDetector(
                  onTap: () =>
                      setState(() => _doNotShowAgain = !_doNotShowAgain),
                  child: const Text(
                    '다시 보지 않기',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
