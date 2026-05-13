import 'package:flutter/material.dart';
import '../services/onboarding_guide_service.dart';

/// 온보딩 말풍선 위젯 + Spotlight 효과.
///
/// [targetKey]로 지정한 위젯 위치를 감지하여
/// 해당 위젯만 밝게 비추고(Spotlight) 나머지를 어둡게 처리합니다.
class OnboardingTooltipOverlay extends StatefulWidget {
  /// 대상 위젯의 GlobalKey
  final GlobalKey targetKey;

  /// 표시할 온보딩 단계
  final OnboardingStep step;

  /// 체험모드 여부 (메시지가 달라짐)
  final bool isDemo;

  /// 말풍선 방향 (기본: 위에 표시)
  final TooltipDirection direction;

  /// 닫기 콜백
  final VoidCallback? onDismiss;

  /// "건너뛰기" 콜백 (전체 가이드 종료)
  final VoidCallback? onSkipAll;

  /// 타겟 위젯의 아이콘/색상 (말풍선 안에 시각적으로 표시)
  final IconData? targetIcon;
  final Color? targetColor;

  const OnboardingTooltipOverlay({
    super.key,
    required this.targetKey,
    required this.step,
    this.isDemo = false,
    this.direction = TooltipDirection.above,
    this.onDismiss,
    this.onSkipAll,
    this.targetIcon,
    this.targetColor,
  });

  /// OverlayEntry를 사용하여 현재 화면 위에 표시.
  static OverlayEntry show({
    required BuildContext context,
    required GlobalKey targetKey,
    required OnboardingStep step,
    bool isDemo = false,
    TooltipDirection direction = TooltipDirection.above,
    VoidCallback? onDismiss,
    VoidCallback? onSkipAll,
    IconData? targetIcon,
    Color? targetColor,
  }) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => OnboardingTooltipOverlay(
        targetKey: targetKey,
        step: step,
        isDemo: isDemo,
        direction: direction,
        targetIcon: targetIcon,
        targetColor: targetColor,
        onDismiss: () {
          entry.remove();
          onDismiss?.call();
        },
        onSkipAll: () {
          entry.remove();
          onSkipAll?.call();
        },
      ),
    );
    Overlay.of(context).insert(entry);
    return entry;
  }

  @override
  State<OnboardingTooltipOverlay> createState() =>
      _OnboardingTooltipOverlayState();
}

enum TooltipDirection { above, below }

class _OnboardingTooltipOverlayState extends State<OnboardingTooltipOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _slideAnim;

  Rect? _targetRect;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<double>(
      begin: 12,
      end: 0,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _findTarget();
      _animCtrl.forward();
    });
  }

  void _findTarget() {
    final renderBox =
        widget.targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final offset = renderBox.localToGlobal(Offset.zero);
      setState(() {
        _targetRect = Rect.fromLTWH(
          offset.dx,
          offset.dy,
          renderBox.size.width,
          renderBox.size.height,
        );
      });
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = OnboardingGuideService.getMessage(
      widget.step,
      isDemo: widget.isDemo,
    );
    final screenSize = MediaQuery.of(context).size;

    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (context, _) {
        return Stack(
          children: [
            // ─── Spotlight 오버레이 ───
            if (_targetRect != null)
              GestureDetector(
                onTap: widget.onDismiss,
                child: CustomPaint(
                  size: screenSize,
                  painter: _SpotlightPainter(
                    targetRect: _targetRect!,
                    opacity: _fadeAnim.value * 0.6,
                  ),
                ),
              )
            else
              GestureDetector(
                onTap: widget.onDismiss,
                child: Container(
                  width: screenSize.width,
                  height: screenSize.height,
                  color: Colors.black.withValues(alpha: _fadeAnim.value * 0.5),
                ),
              ),

            // ─── 말풍선 (타겟 위에 표시) ───
            if (_targetRect != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: widget.direction == TooltipDirection.above
                    ? screenSize.height -
                          _targetRect!.top +
                          20 -
                          _slideAnim.value
                    : null,
                top: widget.direction == TooltipDirection.below
                    ? _targetRect!.bottom + 20 + _slideAnim.value
                    : null,
                child: _buildBubble(message, context),
              ),

            // ─── 아래 화살표 (말풍선 → 타겟을 가리킴) ───
            if (_targetRect != null &&
                widget.direction == TooltipDirection.above)
              Positioned(
                bottom:
                    screenSize.height - _targetRect!.top + 6 - _slideAnim.value,
                left: _targetRect!.center.dx - 14,
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: CustomPaint(
                    size: const Size(28, 14),
                    painter: _ArrowPainter(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBubble(OnboardingMessage message, BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더: 이모지 + 타이틀 + 닫기(X)
              Row(
                children: [
                  Text(message.emoji, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message.title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1a1a2e),
                        height: 1.2,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey, size: 22),
                    onPressed: widget.onDismiss,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 타겟 버튼 시각화 (실제 버튼 모양을 보여줌)
              if (widget.targetIcon != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 실제 FAB 모양 복제
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color:
                                widget.targetColor ?? const Color(0xFF1a1a2e),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (widget.targetColor ??
                                            const Color(0xFF1a1a2e))
                                        .withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            widget.targetIcon!,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '← 이 버튼을 눌러주세요!',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1a1a2e),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              '오른쪽 아래에 있어요',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF888888),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

              if (widget.targetIcon != null) const SizedBox(height: 14),

              // 본문 (큰 글씨 — 50대 가독성)
              Text(
                message.body,
                style: const TextStyle(
                  fontSize: 17,
                  color: Color(0xFF444444),
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 16),

              // 하단 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (widget.onSkipAll != null)
                    TextButton(
                      onPressed: widget.onSkipAll,
                      child: const Text(
                        '가이드 건너뛰기',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    )
                  else
                    const SizedBox(),
                  FilledButton(
                    onPressed: widget.onDismiss,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      '알겠어요! 👍',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),

              // 단계 인디케이터
              const SizedBox(height: 12),
              _buildStepIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    final totalSteps = OnboardingStep.completed.index;
    final currentIdx = widget.step.index;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalSteps, (i) {
        final isActive = i == currentIdx;
        final isCompleted = i < currentIdx;
        return Container(
          width: isActive ? 20 : 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: isActive
                ? const Color(0xFF1565C0)
                : isCompleted
                ? const Color(0xFF90CAF9)
                : const Color(0xFFE0E0E0),
          ),
        );
      }),
    );
  }
}

/// 말풍선 꼬리 (▼) 화살표
class _ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Spotlight 효과: 타겟 영역만 투명하게 잘라내는 CustomPainter
class _SpotlightPainter extends CustomPainter {
  final Rect targetRect;
  final double opacity;

  _SpotlightPainter({required this.targetRect, required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: opacity);

    // 전체를 어둡게
    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // 타겟 영역을 투명하게 잘라냄 (둥근 사각형)
    final spotlightRect = RRect.fromRectAndRadius(
      targetRect.inflate(12), // 넉넉한 여백
      const Radius.circular(16),
    );
    path.addRRect(spotlightRect);
    path.fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // Spotlight 테두리 글로우
    final glowPaint = Paint()
      ..color = Colors.white.withValues(alpha: opacity * 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10);
    canvas.drawRRect(spotlightRect, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.opacity != opacity ||
        oldDelegate.targetRect != targetRect;
  }
}
