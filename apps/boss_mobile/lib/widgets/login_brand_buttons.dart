import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared metrics: unified height, corner radius, and full-width tap targets.
class LoginBrandButtonMetrics {
  LoginBrandButtonMetrics._();

  static const double height = 54;
  static const double borderRadius = 8;
  static const double verticalGap = 12;
}

/// Google Sign-In — light button: white fill, neutral border, official multicolor G,
/// Roboto (per Google Sign-In branding guidelines for button typography).
class GoogleBrandSignInButton extends StatelessWidget {
  const GoogleBrandSignInButton({
    super.key,
    required this.onPressed,
    this.assetPath = 'assets/brands/google_g.svg',
  });

  final VoidCallback? onPressed;
  final String assetPath;

  static const Color _border = Color(0xFF747775);
  static const Color _text = Color(0xFF1F1F1F);

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LoginBrandButtonMetrics.borderRadius),
          side: const BorderSide(color: _border, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(LoginBrandButtonMetrics.borderRadius),
          child: SizedBox(
            height: LoginBrandButtonMetrics.height,
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    assetPath,
                    width: 20,
                    height: 20,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Google로 로그인',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.roboto(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                        color: _text,
                        letterSpacing: 0.15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sign in with Apple — black style (HIG: high contrast, system-style control).
class AppleBrandSignInButton extends StatelessWidget {
  const AppleBrandSignInButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  static const Color _appleBlack = Color(0xFF000000);

  TextStyle _labelStyle(BuildContext context) {
    const base = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.25,
      letterSpacing: -0.24,
      color: Colors.white,
    );
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return base.copyWith(fontFamily: '.SF Pro Text');
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: Material(
        color: _appleBlack,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LoginBrandButtonMetrics.borderRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(LoginBrandButtonMetrics.borderRadius),
          splashColor: Colors.white24,
          highlightColor: Colors.white12,
          child: SizedBox(
            height: LoginBrandButtonMetrics.height,
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.apple, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Apple로 로그인',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: _labelStyle(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fallback email link — same geometry as brand buttons; keeps primary filled style.
class EmailLinkFallbackButton extends StatelessWidget {
  const EmailLinkFallbackButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon = Icons.email_outlined,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: LoginBrandButtonMetrics.height,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        label: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.1),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(LoginBrandButtonMetrics.borderRadius),
          ),
        ),
      ),
    );
  }
}
