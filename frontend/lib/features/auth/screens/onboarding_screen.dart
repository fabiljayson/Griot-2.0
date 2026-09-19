import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/onboarding_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/griot_logo.dart';

/// Onboarding screen shown on the very first app launch.
///
/// Features 3 beautiful slides introducing the Griot AI platform:
/// 1. Welcome — brand introduction with African proverb
/// 2. Explore — discover stories, museums, QR codes
/// 3. Heritage — preserve and share African culture
///
/// After completion, the user proceeds to the login/registration screen.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with TickerProviderStateMixin {
  late final PageController _pageController;
  late final AnimationController _animController;
  int _currentPage = 0;
  static const _totalPages = 3;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
    _animController.reset();
    _animController.forward();
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _skipToEnd() {
    _completeOnboarding();
  }

  void _completeOnboarding() {
    ref.read(onboardingProvider.notifier).completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final isWide = screenWidth >= 720;

    return Scaffold(
      backgroundColor: const Color(0xFF151F42), // Ndop indigo dark
      body: isWide
          ? _buildWideLayout(screenWidth, screenHeight)
          : _buildCompactLayout(screenWidth, screenHeight),
    );
  }

  // ─── Wide layout: side-by-side ──────────────────────────────────────
  Widget _buildWideLayout(double screenWidth, double screenHeight) {
    return Row(
      children: [
        // Left: Page content
        Expanded(
          flex: 5,
          child: _buildPageView(),
        ),
        // Right: Branding & controls
        Expanded(
          flex: 4,
          child: _buildSidePanel(screenWidth),
        ),
      ],
    );
  }

  // ─── Compact layout: stacked ────────────────────────────────────────
  Widget _buildCompactLayout(double screenWidth, double screenHeight) {
    return Column(
      children: [
        // Skip button
        SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topRight,
            child: TextButton(
              onPressed: _skipToEnd,
              child: Text(
                'Skip',
                style: TextStyle(
                  fontFamily: 'PlusJakartaSans',
                  color: AppColors.sand.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        // Page content
        Expanded(
          child: _buildPageView(),
        ),
        // Bottom controls
        _buildBottomControls(isWide: false),
      ],
    );
  }

  // ─── PageView ───────────────────────────────────────────────────────
  Widget _buildPageView() {
    return PageView.builder(
      controller: _pageController,
      itemCount: _totalPages,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        return _OnboardingSlide(
          pageIndex: index,
          animController: _animController,
        );
      },
    );
  }

  // ─── Side panel (wide layout) ──────────────────────────────────────
  Widget _buildSidePanel(double screenWidth) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1E2B58), // Ndop indigo
            Color(0xFF151F42), // Ndop indigo dark
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: screenWidth * 0.05,
            vertical: 40,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // GriotMark
              const GriotMark(size: 72),
              const SizedBox(height: 32),
              // Brand name
              Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontFamily: 'Fraunces',
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    letterSpacing: -0.3,
                  ),
                  children: [
                    TextSpan(
                      text: 'Griot ',
                      style: TextStyle(color: AppColors.sand),
                    ),
                    TextSpan(
                      text: 'AI',
                      style: TextStyle(
                        color: AppColors.ochreDark,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Digital Heritage Platform',
                style: TextStyle(
                  fontFamily: 'PlusJakartaSans',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ochreTint.withValues(alpha: 0.6),
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 48),
              // Page indicator
              _buildPageIndicator(),
              const SizedBox(height: 48),
              // Action button
              _buildActionButton(isWide: true),
              const SizedBox(height: 16),
              // Skip
              TextButton(
                onPressed: _skipToEnd,
                child: Text(
                  'Skip',
                  style: TextStyle(
                    fontFamily: 'PlusJakartaSans',
                    color: AppColors.sand.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Bottom controls (compact layout) ──────────────────────────────
  Widget _buildBottomControls({required bool isWide}) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(context).padding.bottom + 24),
      decoration: const BoxDecoration(
        color: Color(0xFF151F42), // Ndop indigo dark
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPageIndicator(),
          const SizedBox(height: 32),
          _buildActionButton(isWide: false),
        ],
      ),
    );
  }

  // ─── Page indicator dots ───────────────────────────────────────────
  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_totalPages, (index) {
        final isActive = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: isActive ? 28 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.terracotta
                : AppColors.sand.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ─── Action button ─────────────────────────────────────────────────
  Widget _buildActionButton({required bool isWide}) {
    final isLastPage = _currentPage == _totalPages - 1;

    return SizedBox(
      width: isWide ? 220 : double.infinity,
      height: 54,
      child: FilledButton(
        onPressed: _nextPage,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.terracotta,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontFamily: 'PlusJakartaSans',
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(isLastPage ? 'Get Started' : 'Next'),
            const SizedBox(width: 8),
            FaIcon(
              isLastPage ? AppIcons.check : AppIcons.arrow_forward_ios,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  ONBOARDING SLIDE
// ═══════════════════════════════════════════════════════════════════════

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({
    required this.pageIndex,
    required this.animController,
  });

  final int pageIndex;
  final AnimationController animController;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 720;

    final slideData = _slides[pageIndex];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF151F42), // Ndop indigo dark
            Color(0xFF1E2B58), // Ndop indigo
            Color(0xFF2A3B73), // Indigo light
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Decorative pattern
          Positioned.fill(
            child: CustomPaint(
              painter: _AfricanPatternPainter(),
            ),
          ),
          // Warm glow
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(
                    -0.3 + pageIndex * 0.3,
                    -0.2,
                  ),
                  radius: 1.2,
                  colors: [
                    slideData.accentColor.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Content
          Center(
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: animController,
                curve: const Interval(0.0, 0.6),
              ),
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.08),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animController,
                  curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
                )),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 48 : 32,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Icon
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: slideData.accentColor.withValues(alpha: 0.12),
                          border: Border.all(
                            color: slideData.accentColor.withValues(alpha: 0.25),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: FaIcon(
                            slideData.icon,
                            size: 44,
                            color: slideData.accentColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 36),
                      // Title
                      Text(
                        slideData.title,
                        style: TextStyle(
                          fontFamily: 'Fraunces',
                          fontSize: isWide ? 32 : 28,
                          fontWeight: FontWeight.w700,
                          color: AppColors.sand,
                          height: 1.2,
                          letterSpacing: -0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      // Subtitle
                      Text(
                        slideData.subtitle,
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: AppColors.sand.withValues(alpha: 0.7),
                          height: 1.6,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (slideData.quote != null) ...[
                        const SizedBox(height: 28),
                        // Quote
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.terracotta.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.terracotta.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Text(
                            '"${slideData.quote}"',
                            style: TextStyle(
                              fontFamily: 'Fraunces',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              fontStyle: FontStyle.italic,
                              color: AppColors.ochreDark.withValues(alpha: 0.85),
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  SLIDE DATA
// ═══════════════════════════════════════════════════════════════════════

class _SlideData {
  const _SlideData({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.quote,
    required this.accentColor,
  });

  final FaIconData icon;
  final String title;
  final String subtitle;
  final String? quote;
  final Color accentColor;
}

final _slides = [
  _SlideData(
    icon: AppIcons.explore,
    title: 'Discover\nAfrican Heritage',
    subtitle:
        'Explore a rich digital library of cultural tales, oral traditions, and historical artifacts from Cameroon and Central Africa.',
    quote: 'Every artifact has a story to tell.',
    accentColor: AppColors.terracotta,
  ),
  _SlideData(
    icon: AppIcons.qr_code_scanner,
    title: 'Scan &\nExperience',
    subtitle:
        'Scan QR codes at museums and cultural sites to unlock immersive digital experiences with AI-powered narration and video.',
    quote: 'Until the lion learns to write, every story will glorify the hunter.',
    accentColor: AppColors.ochre,
  ),
  _SlideData(
    icon: AppIcons.favorite,
    title: 'Preserve &\nShare',
    subtitle:
        'Contribute stories, earn heritage badges, and help preserve Africa\'s oral traditions for future generations.',
    quote: null,
    accentColor: AppColors.savannahGreen,
  ),
];

// ═══════════════════════════════════════════════════════════════════════
//  DECORATIVE PAINTER
// ═══════════════════════════════════════════════════════════════════════

class _AfricanPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.terracotta.withValues(alpha: 0.03)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const spacing = 70.0;
    final rows = (size.height / spacing).ceil();
    final cols = (size.width / spacing).ceil();

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final cx = c * spacing + spacing / 2;
        final cy = r * spacing + spacing / 2;
        final half = spacing * 0.25;

        // Diamond
        final path = Path()
          ..moveTo(cx, cy - half)
          ..lineTo(cx + half, cy)
          ..lineTo(cx, cy + half)
          ..lineTo(cx - half, cy)
          ..close();
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
