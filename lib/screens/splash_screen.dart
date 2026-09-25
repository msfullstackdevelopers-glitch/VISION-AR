import 'package:flutter/material.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  // ================================================================
  // BACKGROUND IMAGE PRELOADING — fixes the "blank then pops in" bug
  // ================================================================
  //
  // ROOT CAUSE: `DecorationImage(image: AssetImage(...))` only starts
  // fetching + decoding the image the first time it is painted. On
  // localhost that's basically instant (dev server serves files
  // straight from disk). On the real domain (app.visionar.tech) the
  // browser has to fetch the image bytes over the network the first
  // time, which can take a noticeable moment — and during that time
  // there's nothing to paint for the DecorationImage, so the screen
  // looks blank/flat black until it suddenly pops in.
  //
  // FIX: explicitly `precacheImage()` every background variant right
  // when this screen is created, track which ones are ready, and only
  // fade the real photo in once it has actually finished loading.
  // While it's loading we show a themed gradient + small spinner
  // instead of a flat blank screen. We also warm up the Login
  // screen's backgrounds here (fire-and-forget) so that by the time
  // the user taps a button, that screen's photo is already cached.
  static const List<String> _splashAssets = [
    'assets/images/splash_bg_mobile.png',
    'assets/images/splash_bg_tablet.png',
    'assets/images/splash_bg_desktop.png',
  ];

  static const List<String> _loginAssets = [
    'assets/images/login_bg_mobile.png',
    'assets/images/login_bg_tablet.png',
    'assets/images/login_bg_desktop.png',
  ];

  final Set<String> _loadedAssets = {};
  bool _warmupStarted = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeIn,
      ),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );

    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warmUpBackgrounds();
  }

  void _warmUpBackgrounds() {
    if (_warmupStarted) return;
    _warmupStarted = true;

    // Preload every splash background variant so resizing between
    // mobile/tablet/desktop breakpoints never re-triggers a blank
    // flash either.
    for (final asset in _splashAssets) {
      _precache(asset);
    }

    // Fire-and-forget: warm the Login screen's backgrounds too, so
    // the next screen's photo appears instantly instead of blank.
    for (final asset in _loginAssets) {
      precacheImage(AssetImage(asset), context);
    }
  }

  Future<void> _precache(String asset) async {
    try {
      await precacheImage(AssetImage(asset), context);
    } catch (e) {
      debugPrint('DEBUG: precache failed for $asset -> $e');
      // If it fails we simply keep showing the placeholder gradient;
      // the DecorationImage below will still try to load normally.
    }
    if (mounted) {
      setState(() => _loadedAssets.add(asset));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const LoginScreen(),
      ),
    );
  }

  // ---- Responsive breakpoints (inline, no separate file) ----
  bool _isTablet(double width) => width >= 650 && width < 1100;
  bool _isDesktop(double width) => width >= 1100;

  /// Screen width ke hisaab se sahi background image asset return karta hai.
  /// Teeno images pubspec.yaml me declare hona chahiye:
  ///   assets/images/splash_bg_mobile.png
  ///   assets/images/splash_bg_tablet.png
  ///   assets/images/splash_bg_desktop.png
  String _backgroundAsset(double width) {
    if (_isDesktop(width)) {
      return 'assets/images/splash_bg_desktop.png';
    } else if (_isTablet(width)) {
      return 'assets/images/splash_bg_tablet.png';
    }
    return 'assets/images/splash_bg_mobile.png';
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = _isDesktop(width);
    final isTablet = _isTablet(width);
    final bgAsset = _backgroundAsset(width);
    final bool bgReady = _loadedAssets.contains(bgAsset);

    // Content ki max-width - mobile par full width, tablet/desktop par
    // ek centered, narrow column taaki UI stretch na ho.
    final double maxContentWidth =
    isDesktop ? 480 : (isTablet ? 440 : double.infinity);

    // Screen size ke hisaab se side padding.
    final double horizontalPadding = isDesktop ? 48 : (isTablet ? 40 : 24);

    return Scaffold(
      // FIX: a dark themed base color instead of Scaffold's default,
      // so even the very first frame (before the Stack below even
      // paints) looks intentional rather than an unstyled flash.
      backgroundColor: const Color(0xFF0B0F14),

      body: Stack(
        fit: StackFit.expand,
        children: [
          // Always-visible themed placeholder — there is never a
          // literal flat/blank frame while the real photo loads.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0B0F14), Color(0xFF161C22)],
              ),
            ),
          ),

          // Real background photo — fades in only once it's actually
          // finished precaching, instead of popping in abruptly.
          AnimatedOpacity(
            opacity: bgReady ? 1 : 0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            child: Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(bgAsset),
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
              ),
            ),
          ),

          // Small, unobtrusive loading indicator while the photo is
          // still on its way in — tells the user something IS
          // happening instead of the screen looking stuck/broken.
          if (!bgReady)
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Color(0xFFD4A843),
                  ),
                ),
              ),
            ),

          Container(
            // Desktop/web par background image poori width tak stretch
            // hoti hai, isliye halka dark overlay taaki text/buttons
            // readable rahein.
            color: (isDesktop || isTablet)
                ? Colors.black.withOpacity(0.35)
                : Colors.transparent,
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      const Spacer(flex: 2),

                      // Logo / brand block with fade + scale animation


                      const Spacer(flex: 3),

                      Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding),
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _goToLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFD4A843),
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 8,
                                  shadowColor:
                                  const Color(0xFFD4A843).withOpacity(0.4),
                                ),
                                child: const Text(
                                  'Get Started',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: OutlinedButton(
                                onPressed: _goToLogin,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Login / Sign Up',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 40),
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

  Widget _buildLetter(String letter, Color color, double size) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 2,
        ),
      ),
    );
  }
}