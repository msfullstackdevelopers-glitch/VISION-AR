import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

class OTPScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;

  const OTPScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
  });

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  final TextEditingController otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool isLoading = false;
  int resendSeconds = 60;

  // ================================================================
  // BACKGROUND IMAGE PRELOADING — fixes the "blank then pops in" bug
  // ================================================================
  //
  // Same fix as SplashScreen / LoginScreen. This screen reuses the
  // exact same `login_bg_*` assets, so in the normal flow (Login ->
  // OTP) they are usually already cached by the time we get here —
  // but we still precache defensively in case this screen is ever
  // reached directly (deep link, hot restart, etc).
  static const List<String> _bgAssets = [
    'assets/images/login_bg_mobile.png',
    'assets/images/login_bg_tablet.png',
    'assets/images/login_bg_desktop.png',
  ];

  final Set<String> _loadedAssets = {};
  bool _warmupStarted = false;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

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
    // If Flutter's ImageCache already has it (e.g. LoginScreen already
    // precached it), this resolves immediately with no extra network
    // fetch — so calling it again here is cheap and safe.
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
    otpController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));

      if (mounted && resendSeconds > 0) {
        setState(() {
          resendSeconds--;
        });
      }

      return mounted && resendSeconds > 0;
    });
  }

  Future<void> _verifyOTP() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isLoading = true;
    });

    // DEBUG: verificationId aur entered OTP check karo - agar verificationId
    // khaali/null jaisa dikhe to matlab pichli screen se hi sahi value nahi aayi.
    debugPrint('DEBUG: Verifying OTP -> verificationId: ${widget.verificationId}, code: ${otpController.text.trim()}');

    try {
      final PhoneAuthCredential credential =
      PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: otpController.text.trim(),
      );

      await _auth.signInWithCredential(credential);

      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('isLoggedIn', true);

      if (mounted) {
        setState(() {
          isLoading = false;
        });

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const HomeScreen(),
          ),
              (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      // DEBUG: exact Firebase error code (e.g. 'invalid-verification-code',
      // 'session-expired') yahan milega.
      debugPrint('DEBUG: _verifyOTP FirebaseAuthException -> code: ${e.code}, message: ${e.message}');

      if (mounted) {
        setState(() {
          isLoading = false;
        });

        _showError(
          e.message ?? 'Invalid OTP',
        );
      }
    } catch (e) {
      debugPrint('DEBUG: _verifyOTP unexpected error -> $e');

      if (mounted) {
        setState(() {
          isLoading = false;
        });

        _showError(
          e.toString(),
        );
      }
    }
  }

  Future<void> _resendOTP() async {
    if (resendSeconds > 0) return;

    setState(() {
      isLoading = true;
    });

    debugPrint('DEBUG: Resending OTP to ${widget.phoneNumber}');

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber,

        verificationCompleted:
            (PhoneAuthCredential credential) async {
          debugPrint('DEBUG: (resend) verificationCompleted fired');
        },

        verificationFailed:
            (FirebaseAuthException e) {
          // DEBUG: exact resend error code/message.
          debugPrint('DEBUG: (resend) verificationFailed -> code: ${e.code}, message: ${e.message}');

          if (mounted) {
            setState(() {
              isLoading = false;
            });

            _showError(
              e.message ?? 'Resend failed',
            );
          }
        },

        codeSent:
            (String verificationId, int? resendToken) {
          debugPrint('DEBUG: (resend) codeSent -> verificationId: $verificationId');

          if (mounted) {
            setState(() {
              isLoading = false;
              resendSeconds = 60;
            });

            _startResendTimer();

            _showError(
              'OTP resent successfully',
              isError: false,
            );
          }
        },

        codeAutoRetrievalTimeout:
            (String verificationId) {},

        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      debugPrint('DEBUG: (resend) Outer catch -> $e');

      if (mounted) {
        setState(() {
          isLoading = false;
        });

        _showError(
          e.toString(),
        );
      }
    }
  }

  void _showError(
      String message, {
        bool isError = true,
      }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
        isError ? Colors.red : Colors.green,
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

    // Heading aur OTP box sizes responsive.
    final double headingFontSize = isDesktop ? 30 : (isTablet ? 28 : 26);
    final double pinBoxSize = isDesktop ? 60 : (isTablet ? 56 : 52);
    final double pinBoxHeight = isDesktop ? 66 : (isTablet ? 62 : 58);
    final double buttonHeight = isDesktop ? 58 : (isTablet ? 56 : 54);

    // Default OTP boxes
    final defaultPinTheme = PinTheme(
      width: pinBoxSize,
      height: pinBoxHeight,

      textStyle: TextStyle(
        fontSize: isDesktop ? 24 : 22,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),

      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.38),

        borderRadius: BorderRadius.circular(14),

        border: Border.all(
          color: Colors.white.withOpacity(0.18),
        ),
      ),
    );

    // Focused OTP box
    final focusedPinTheme =
    defaultPinTheme.copyDecorationWith(
      color: Colors.black.withOpacity(0.48),

      border: Border.all(
        color: const Color(0xFFD4A843),
        width: 2,
      ),
    );

    // Submitted OTP box
    final submittedPinTheme =
    defaultPinTheme.copyDecorationWith(
      color: const Color(0xFFD4A843)
          .withOpacity(0.12),

      border: Border.all(
        color: const Color(0xFFD4A843),
        width: 2,
      ),
    );

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
            // Dark transparent overlay
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(
                (isDesktop || isTablet) ? 0.48 : 0.40,
              ),
            ),

            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),

                    child: Form(
                      key: _formKey,

                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,

                        children: [
                          const SizedBox(height: 20),

                          // Back Button
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                            },

                            child: Container(
                              padding:
                              const EdgeInsets.all(8),

                              decoration: BoxDecoration(
                                color: Colors.black
                                    .withOpacity(0.35),

                                borderRadius:
                                BorderRadius.circular(10),

                                border: Border.all(
                                  color: Colors.white
                                      .withOpacity(0.12),
                                ),
                              ),

                              child: const Icon(
                                Icons.arrow_back_ios_new,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),

                          SizedBox(height: isDesktop ? 64 : 55),

                          Text(
                            'Enter verification code',
                            style: TextStyle(
                              fontSize: headingFontSize,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Phone number message
                          RichText(
                            text: TextSpan(
                              text: 'We sent a code to ',

                              style: TextStyle(
                                fontSize: isDesktop ? 15 : 14,
                                color: Colors.white
                                    .withOpacity(0.65),
                                height: 1.5,
                              ),

                              children: [
                                TextSpan(
                                  text: widget.phoneNumber,

                                  style: const TextStyle(
                                    color: Color(0xFFD4A843),
                                    fontWeight:
                                    FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          SizedBox(height: isDesktop ? 48 : 40),

                          // OTP Boxes
                          Center(
                            child: Pinput(
                              length: 6,

                              controller: otpController,

                              defaultPinTheme:
                              defaultPinTheme,

                              focusedPinTheme:
                              focusedPinTheme,

                              submittedPinTheme:
                              submittedPinTheme,

                              keyboardType:
                              TextInputType.number,

                              validator: (value) {
                                if (value == null ||
                                    value.isEmpty) {
                                  return 'Enter OTP';
                                }

                                if (value.length != 6) {
                                  return 'Enter 6 digit OTP';
                                }

                                return null;
                              },

                              pinputAutovalidateMode:
                              PinputAutovalidateMode
                                  .onSubmit,

                              showCursor: true,

                              onCompleted: (pin) {
                                _verifyOTP();
                              },
                            ),
                          ),

                          SizedBox(height: isDesktop ? 36 : 32),

                          // Resend OTP
                          Center(
                            child: resendSeconds > 0
                                ? Text(
                              'Resend code in '
                                  '${resendSeconds}s',

                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white
                                    .withOpacity(0.5),
                              ),
                            )
                                : TextButton(
                              onPressed:
                              _resendOTP,

                              child: const Text(
                                'Resend Code',

                                style: TextStyle(
                                  color:
                                  Color(0xFFD4A843),
                                  fontSize: 15,
                                  fontWeight:
                                  FontWeight.w600,
                                ),
                              ),
                            ),
                          ),

                          // Mobile par Spacer se button neeche push hota hai.
                          // Tablet/Desktop par fixed gap use karte hain taaki
                          // form card ke saath compact rahe.
                          if (isDesktop || isTablet)
                            const SizedBox(height: 48)
                          else
                            const Spacer(),

                          // Verify Button
                          SizedBox(
                            width: double.infinity,
                            height: buttonHeight,

                            child: ElevatedButton(
                              onPressed: isLoading
                                  ? null
                                  : _verifyOTP,

                              style:
                              ElevatedButton.styleFrom(
                                backgroundColor:
                                const Color(0xFFD4A843),

                                foregroundColor:
                                Colors.black,

                                disabledBackgroundColor:
                                const Color(0xFFD4A843)
                                    .withOpacity(0.55),

                                shape:
                                RoundedRectangleBorder(
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
                                  AlwaysStoppedAnimation<
                                      Color>(
                                    Colors.black,
                                  ),
                                ),
                              )
                                  : Text(
                                'Verify',

                                style: TextStyle(
                                  fontSize: isDesktop ? 18 : 17,
                                  fontWeight:
                                  FontWeight.w600,
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