import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/onboarding_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/auth_form_widgets.dart';
import '../../../core/widgets/brand_widgets.dart';

/// Onboarding screen shown on the very first app launch.
///
/// Three slides introducing the Griot AI platform:
/// 1. Welcome — brand introduction with African proverb
/// 2. Explore — discover stories, museums, QR codes
/// 3. Heritage — preserve and share African culture
///
/// After completion, the user proceeds to the login/registration screen.
///
/// This screen used to paint itself: a hardcoded `#151F42` indigo background,
/// its own copy of the kente pattern painter, and hand-rolled `TextStyle`s. It
/// was the only screen in the app not built on the shared shell, so it read as
/// a different product from the login screen one swipe away. It now uses
/// [BrandScaffold] — the same branding panel, header, pattern and breakpoint
/// as login and register — and takes every colour and font from the theme, so
/// the three surfaces cannot drift apart again.
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
    // BrandScaffold supplies the brand panel (wide) or brand header (compact),
    // plus the shared kente pattern and the 720px breakpoint. The controller
    // is passed through so the brand panel animates in step with the slides,
    // which is what LoginScreen does.
    return BrandScaffold(
      animController: _animController,
      child: _OnboardingPanel(
        pageController: _pageController,
        animController: _animController,
        currentPage: _currentPage,
        totalPages: _totalPages,
        onPageChanged: _onPageChanged,
        onNext: _nextPage,
        onSkip: _skipToEnd,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  ONBOARDING PANEL (the content side of BrandScaffold)
// ═══════════════════════════════════════════════════════════════════════

class _OnboardingPanel extends StatelessWidget {
  const _OnboardingPanel({
    required this.pageController,
    required this.animController,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
    required this.onNext,
    required this.onSkip,
  });

  final PageController pageController;
  final AnimationController animController;
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isWide = MediaQuery.sizeOf(context).width >= kAuthBreakpointWide;

    return Container(
      // Mirrors the login form panel: an opaque surface on wide layouts (where
      // it sits beside the brand panel) and transparent on compact ones,
      // where it sits directly under the brand header.
      color: isWide ? scheme.surface : Colors.transparent,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Skip, top-right. Inside SafeArea so it clears the status bar on
            // compact layouts without double-padding under the brand header.
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: onSkip,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: pageController,
                itemCount: totalPages,
                onPageChanged: onPageChanged,
                itemBuilder: (context, index) => _OnboardingSlide(
                  slide: _slides[index],
                  animController: animController,
                ),
              ),
            ),
            _OnboardingControls(
              currentPage: currentPage,
              totalPages: totalPages,
              onNext: onNext,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  CONTROLS — page dots + primary action
// ═══════════════════════════════════════════════════════════════════════

class _OnboardingControls extends StatelessWidget {
  const _OnboardingControls({
    required this.currentPage,
    required this.totalPages,
    required this.onNext,
  });

  final int currentPage;
  final int totalPages;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final isLastPage = currentPage == totalPages - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PageIndicator(currentPage: currentPage, totalPages: totalPages),
          const SizedBox(height: 28),
          // AuthButton is the same primary action login and register use, so
          // "Get Started" here and "Sign In" one swipe later are the same
          // button.
          AuthButton(
            onPressed: onNext,
            label: isLastPage ? 'Get Started' : 'Next',
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  PAGE INDICATOR DOTS
// ═══════════════════════════════════════════════════════════════════════

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.currentPage, required this.totalPages});

  final int currentPage;
  final int totalPages;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalPages, (index) {
        final isActive = index == currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: isActive ? 28 : 8,
          height: 8,
          decoration: BoxDecoration(
            // `secondary` is the theme's bronze accent, so the dots pick up a
            // palette change rather than hard-coding one.
            color: isActive
                ? scheme.secondary
                : scheme.onSurfaceVariant.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  ONBOARDING SLIDE
// ═══════════════════════════════════════════════════════════════════════

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({required this.slide, required this.animController});

  final _SlideData slide;
  final AnimationController animController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= kAuthBreakpointWide;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 48 : 24),
      child: Center(
        child: ConstrainedBox(
          // Same measure as the login form panel, so the two read as one
          // column of content rather than two unrelated ones.
          constraints: const BoxConstraints(maxWidth: 400),
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: animController,
              curve: const Interval(0.0, 0.6),
            ),
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animController,
                      curve: const Interval(
                        0.0,
                        0.6,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                  ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SlideHero(slide: slide, height: isWide ? 220 : 170),
                  SizedBox(height: isWide ? 32 : 24),
                  // Fraunces display style from the theme; the size steps up
                  // on wide layouts without leaving the type scale.
                  Text(
                    slide.title,
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontSize: isWide ? 32 : 28,
                      height: 1.2,
                      letterSpacing: -0.3,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    slide.subtitle,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (slide.quote != null) ...[
                    const SizedBox(height: 28),
                    _QuoteCard(quote: slide.quote!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Image-led hero with a branded feature marker.
///
/// The marker is a white badge carrying the slide's accent as the glyph
/// colour, which keeps contrast in the right direction on every accent
/// instead of flipping between white and charcoal per slide.
class _SlideHero extends StatelessWidget {
  const _SlideHero({required this.slide, required this.height});

  final _SlideData slide;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(slide.imageAsset, fit: BoxFit.cover),
            Positioned(
              left: 16,
              bottom: 16,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Icon(slide.icon, size: 19, color: slide.accentColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Proverb card, matching the one in `BrandPanel`.
///
/// `accentTextStrong` is the WCAG AA bronze for small text on white — the
/// plain bronze only reaches ~2.8:1, which is why the quote is not simply
/// `AppColors.bronze`.
class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.quote});

  final String quote;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.bronze.withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        '"$quote"',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontFamily: 'Fraunces',
          fontStyle: FontStyle.italic,
          color: AppColors.accentTextStrong,
          height: 1.5,
        ),
        textAlign: TextAlign.center,
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
    required this.imageAsset,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    this.quote,
  });

  final IconData icon;
  final String imageAsset;
  final String title;
  final String subtitle;

  /// Glyph colour for the hero marker. All three are the "strong" accent
  /// variants — they clear 4.5:1 as small marks on a white badge, where the
  /// base bronze does not.
  final Color accentColor;

  final String? quote;
}

final _slides = [
  _SlideData(
    icon: AppIcons.explore,
    imageAsset: 'assets/imagery/onboarding/discover-heritage.jpg',
    title: 'Discover\nAfrican Heritage',
    subtitle:
        'Explore a rich digital library of cultural tales, oral traditions, and historical artifacts from Cameroon and Central Africa.',
    quote: 'Every artifact has a story to tell.',
    accentColor: AppColors.accentTextStrong,
  ),
  _SlideData(
    icon: AppIcons.qr_code_scanner,
    imageAsset: 'assets/imagery/onboarding/scan-experience.jpg',
    title: 'Scan &\nExperience',
    subtitle:
        'Scan QR codes at museums and cultural sites to unlock immersive digital experiences with AI-powered narration and video.',
    quote:
        'Until the lion learns to write, every story will glorify the hunter.',
    accentColor: AppColors.accentTextStrongIndigo,
  ),
  _SlideData(
    icon: AppIcons.favorite,
    imageAsset: 'assets/imagery/onboarding/preserve-share.jpg',
    title: 'Preserve &\nShare',
    subtitle:
        'Contribute stories, earn heritage badges, and help preserve Africa\'s oral traditions for future generations.',
    accentColor: AppColors.accentTextStrongGreen,
  ),
];