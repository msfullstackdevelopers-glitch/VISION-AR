import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'otp_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool isLoading = false;

  // ================================================================
  // BACKGROUND IMAGE PRELOADING — fixes the "blank then pops in" bug
  // ================================================================
  //
  // Same root cause as everywhere else this background pattern is
  // used: `DecorationImage(image: AssetImage(...))` only starts
  // fetching + decoding the file the first time it's painted. On
  // localhost that's instant; on the live domain the browser has to
  // fetch it over the network the first time, so the screen looks
  // blank/flat until it suddenly pops in.
  //
  // FIX: precache every variant of this screen's background as soon
  // as the screen is created, and only fade the real photo in once
  // it has actually finished loading — showing a themed placeholder
  // instead of a flat blank screen in the meantime. Because the OTP
  // screen re-uses these exact same asset paths, this also makes the
  // OTP screen's background load instantly with no extra work.
  static const List<String> _bgAssets = [
    'assets/images/login_bg_mobile.png',
    'assets/images/login_bg_tablet.png',
    'assets/images/login_bg_desktop.png',
  ];

  final Set<String> _loadedAssets = {};
  bool _warmupStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warmUpBackgrounds();
  }

  void _warmUpBackgrounds() {
    if (_warmupStarted) return;
    _warmupStarted = true;

    for (final asset in _bgAssets) {
      _precache(asset);
    }
  }

  Future<void> _precache(String asset) async {
    try {
      await precacheImage(AssetImage(asset), context);
    } catch (e) {
      debugPrint('DEBUG: precache failed for $asset -> $e');
    }
    if (mounted) {
      setState(() => _loadedAssets.add(asset));
    }
  }

  @override
  void dispose() {
    phoneController.dispose();
    super.dispose();
  }

  Future<void> _verifyPhoneNumber() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    final phoneNumber = '+91${phoneController.text.trim()}';

    // DEBUG: exact phone number jo Firebase ko bheja ja raha hai.
    // Console me ise check karke confirm karo format sahi hai
    // (jaise +919876543210, koi extra space/zero nahi hona chahiye).
    debugPrint('DEBUG: Calling verifyPhoneNumber with phoneNumber = $phoneNumber');

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,

        verificationCompleted: (PhoneAuthCredential credential) async {
          if (!mounted) return;

          debugPrint('DEBUG: verificationCompleted fired (auto-retrieval)');

          setState(() => isLoading = true);

          try {
            await _auth.signInWithCredential(credential);

            if (mounted) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) => const HomeScreen(),
                ),
                    (route) => false,
              );
            }
          } catch (e) {
            debugPrint('DEBUG: signInWithCredential (auto) failed -> $e');
            if (mounted) {
              setState(() => isLoading = false);
              _showError('Auto verification failed');
            }
          }
        },

        verificationFailed: (FirebaseAuthException e) {
          // DEBUG: Ye sabse important print hai. Yahan Firebase ka
          // exact error code aur message milta hai (e.g. 'invalid-phone-number',
          // 'too-many-requests', 'captcha-check-failed', 'app-not-authorized').
          debugPrint('DEBUG: verificationFailed -> code: ${e.code}, message: ${e.message}, plugin: ${e.plugin}');

          if (mounted) {
            setState(() => isLoading = false);
            _showError(e.message ?? 'Verification failed');
          }
        },

        codeSent: (String verificationId, int? resendToken) {
          debugPrint('DEBUG: codeSent fired -> verificationId: $verificationId, resendToken: $resendToken');

          if (mounted) {
            setState(() => isLoading = false);

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => OTPScreen(
                  phoneNumber: phoneNumber,
                  verificationId: verificationId,
                ),
              ),
            );
          }
        },

        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint('DEBUG: codeAutoRetrievalTimeout -> verificationId: $verificationId');
        },

        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      // DEBUG: Agar verifyPhoneNumber() khud exception throw kare
      // (network issue, invalid API key, etc.), wo yahan pakda jaayega.
      debugPrint('DEBUG: Outer catch in _verifyPhoneNumber -> $e');

      if (mounted) {
        setState(() => isLoading = false);
        _showError(e.toString());
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---- Responsive breakpoints (inline, same pattern as SplashScreen) ----
  bool _isTablet(double width) => width >= 650 && width < 1100;
  bool _isDesktop(double width) => width >= 1100;

  /// Screen width ke hisaab se sahi background image asset return karta hai.
  /// Teeno images pubspec.yaml me declare hona chahiye:
  ///   assets/images/login_bg_mobile.png
  ///   assets/images/login_bg_tablet.png
  ///   assets/images/login_bg_desktop.png
  String _backgroundAsset(double width) {
    if (_isDesktop(width)) {
      return 'assets/images/login_bg_desktop.png';
    } else if (_isTablet(width)) {
      return 'assets/images/login_bg_tablet.png';
    }
    return 'assets/images/login_bg_mobile.png';
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
    final double horizontalPadding = isDesktop ? 48 : (isTablet ? 40 : 28);

    // Heading aur subtext ke liye responsive font sizes.
    final double headingFontSize = isDesktop ? 30 : (isTablet ? 28 : 26);
    final double subTextFontSize = isDesktop ? 15 : 14;

    // Button height thoda bada tablet/desktop par.
    final double buttonHeight = isDesktop ? 58 : (isTablet ? 56 : 54);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      // FIX: themed base color instead of default, so the very first
      // frame (before the Stack below paints) already looks intentional.
      backgroundColor: const Color(0xFF0B0F14),

      body: Stack(
        fit: StackFit.expand,
        children: [
          // Always-visible themed placeholder — never a literal
          // flat/blank frame while the real photo loads.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0B0F14), Color(0xFF161C22)],
              ),
            ),
          ),

          // Real background photo — fades in only once precached,
          // instead of popping in abruptly.
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
            // Dark transparent overlay so text remains readable.
            // Desktop/tablet par background zyada stretch hoti hai isliye
            // thoda darker overlay use kiya hai.
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(
                (isDesktop || isTablet) ? 0.45 : 0.38,
              ),
            ),

            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Padding(
                    padding:
                    EdgeInsets.symmetric(horizontal: horizontalPadding),

                    child: Form(
                      key: _formKey,

                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          const SizedBox(height: 20),

                          // Back Button
                          GestureDetector(
                            onTap: () => Navigator.pop(context),

                            child: Container(
                              padding: const EdgeInsets.all(8),

                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.35),
                                borderRadius: BorderRadius.circular(10),

                                border: Border.all(
                                  color: Colors.white.withOpacity(0.12),
                                ),
                              ),

                              child: const Icon(
                                Icons.arrow_back_ios_new,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),

                          SizedBox(height: isDesktop ? 40 : 32),

                          // Heading
                          Text(
                            'Enter your mobile number',
                            style: TextStyle(
                              fontSize: headingFontSize,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),

                          const SizedBox(height: 10),

                          Text(
                            'We will send you a verification code to confirm your identity.',
                            style: TextStyle(
                              fontSize: subTextFontSize,
                              color: Colors.white.withOpacity(0.65),
                              height: 1.5,
                            ),
                          ),

                          SizedBox(height: isDesktop ? 48 : 40),

                          // Mobile Number Field
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.38),

                              borderRadius: BorderRadius.circular(16),

                              border: Border.all(
                                color: Colors.white.withOpacity(0.15),
                              ),
                            ),

                            child: Row(
                              children: [
                                // Country Code
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 18,
                                  ),

                                  child: Row(
                                    children: [
                                      const Text(
                                        '🇮🇳',
                                        style: TextStyle(
                                          fontSize: 20,
                                        ),
                                      ),

                                      const SizedBox(width: 8),

                                      Text(
                                        '+91',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.white.withOpacity(0.9),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Divider
                                Container(
                                  width: 1,
                                  height: 30,
                                  color: Colors.white.withOpacity(0.15),
                                ),

                                // Phone Input
                                Expanded(
                                  child: TextFormField(
                                    controller: phoneController,

                                    keyboardType: TextInputType.phone,

                                    maxLength: 10,

                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      letterSpacing: 1.5,
                                    ),

                                    decoration: InputDecoration(
                                      counterText: '',
                                      hintText: '00000 00000',

                                      hintStyle: TextStyle(
                                        color: Colors.white.withOpacity(0.35),
                                        fontSize: 18,
                                      ),

                                      contentPadding:
                                      const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),

                                      border: InputBorder.none,
                                    ),

                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter mobile number';
                                      }

                                      if (value.length != 10) {
                                        return 'Enter valid 10 digit number';
                                      }

                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Mobile par Spacer se button neeche push hota hai.
                          // Tablet/Desktop par fixed gap use karte hain taaki
                          // form card ke saath compact rahe.
                          if (isDesktop || isTablet)
                            const SizedBox(height: 48)
                          else
                            const Spacer(),

                          // Continue Button
                          SizedBox(
                            width: double.infinity,
                            height: buttonHeight,

                            child: ElevatedButton(
                              onPressed:
                              isLoading ? null : _verifyPhoneNumber,

                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                const Color(0xFFD4A843),

                                foregroundColor: Colors.black,

                                disabledBackgroundColor:
                                const Color(0xFFD4A843)
                                    .withOpacity(0.55),

                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                  BorderRadius.circular(14),
                                ),

                                elevation: 8,

                                shadowColor:
                                const Color(0xFFD4A843)
                                    .withOpacity(0.4),
                              ),

                              child: isLoading
                                  ? const SizedBox(
                                height: 22,
                                width: 22,

                                child:
                                CircularProgressIndicator(
                                  strokeWidth: 2.5,

                                  valueColor:
                                  AlwaysStoppedAnimation<Color>(
                                    Colors.black,
                                  ),
                                ),
                              )
                                  : Text(
                                'Continue',

                                style: TextStyle(
                                  fontSize: isDesktop ? 18 : 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),

                          SizedBox(height: isDesktop ? 48 : 40),
                        ],
                      ),
                    ),
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