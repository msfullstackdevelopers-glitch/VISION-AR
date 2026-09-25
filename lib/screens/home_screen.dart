import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import 'package:visionar/screens/home/Home_Content.dart';
import 'package:visionar/screens/home/models_list_screen.dart';
import 'package:visionar/screens/home/models_screen.dart';
import 'package:visionar/screens/home_screen.dart';

import 'home/side_drawer.dart';
import 'home/discover_screen.dart';
import 'home/saved_screen.dart';
import 'home/profile_screen.dart';
import 'home/scan_qr_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // FIX: this used to be a `final` field read ONCE from
  // `FirebaseAuth.instance.currentUser` at the moment HomeScreen was
  // constructed:
  //
  //   final User? _currentUser = FirebaseAuth.instance.currentUser;
  //
  // On Flutter Web (and sometimes on cold starts elsewhere), Firebase
  // Auth's session restore is asynchronous. If HomeScreen builds
  // before that restore finishes, `currentUser` is briefly `null` —
  // and because this was captured only once, the app bar was stuck
  // showing "Welcome" / "Not linked" forever, and `_userRef` pointed
  // at the fake path `users/unknown`, so nothing ever loaded into it.
  // That's exactly what the screenshot showed.
  //
  // Now we listen to `authStateChanges()` for the whole lifetime of
  // this screen and rebuild whenever the real user becomes available
  // (or signs out), instead of reading it a single time.
  User? _currentUser;
  StreamSubscription<User?>? _authSub;

  // Realtime Database reference: users/{uid} -> holds name & photoUrl,
  // same node that the Profile / Edit-Profile screens write to.
  late DatabaseReference _userRef;

  final List<Widget> _screens = const [
    HomeContent(),
    ModelsScreen(),
    ScanQRScreen(),
    SavedScreen(),
    ProfileScreen(),
  ];

  // Shared nav item data so mobile bottom-bar and desktop/tablet top-bar
  // stay perfectly in sync (same icons, same labels, same order).
  static const List<_NavData> _navData = [
    _NavData(icon: Icons.home_rounded, label: 'Home'),
    _NavData(icon: Icons.folder_copy_outlined, label: 'Projects'),
    _NavData(icon: Icons.qr_code_scanner_rounded, label: 'Scan QR'),
    _NavData(icon: Icons.bookmark_border_rounded, label: 'Saved'),
    _NavData(icon: Icons.person_outline_rounded, label: 'Profile'),
  ];

  @override
  void initState() {
    super.initState();

    _currentUser = FirebaseAuth.instance.currentUser;
    _userRef = FirebaseDatabase.instance.ref(
      'users/${_currentUser?.uid ?? 'unknown'}',
    );

    // Keep listening for the entire lifetime of this screen. This
    // fires immediately with the current user (or null), and again
    // whenever Auth finishes restoring the session, or the user
    // signs in/out while this screen happens to be alive.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      if (user?.uid == _currentUser?.uid) return; // nothing changed

      setState(() {
        _currentUser = user;
        _userRef = FirebaseDatabase.instance.ref(
          'users/${user?.uid ?? 'unknown'}',
        );
      });
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  // ---- Responsive breakpoints (same pattern as Login/OTP/Splash) ----
  bool _isTablet(double width) => width >= 650 && width < 1100;
  bool _isDesktop(double width) => width >= 1100;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = _isDesktop(width);
    final isTablet = _isTablet(width);

    // Mobile => bottom nav bar. Tablet/Desktop => nav moves to the app bar.
    final bool useTopNav = isDesktop || isTablet;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFF070D12),

      drawer: const SideDrawer(),

      appBar: _buildAppBar(useTopNav: useTopNav, isDesktop: isDesktop),

      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),

      // Bottom nav bar sirf mobile par dikhta hai. Tablet/Desktop par
      // ye poora widget hi null ho jaata hai kyunki nav app bar me
      // shift ho chuka hota hai.
      bottomNavigationBar: useTopNav ? null : _buildBottomNav(),
    );
  }

  // ==========================================================
  // BOTTOM NAV — mobile only. Same layout/behaviour as before,
  // with a special circular "Scan QR" button in the center.
  // ==========================================================
  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF080E13),
        border: Border(
          top: BorderSide(
            color: Colors.white10,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              _navItem(
                icon: _navData[0].icon,
                label: _navData[0].label,
                index: 0,
              ),
              _navItem(
                icon: _navData[1].icon,
                label: _navData[1].label,
                index: 1,
              ),

              // Center Scan QR button
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _currentIndex = 2;
                    });
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFF182128),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white12,
                          ),
                        ),
                        child: Icon(
                          Icons.qr_code_scanner_rounded,
                          size: 25,
                          color: _currentIndex == 2
                              ? const Color(0xFFD4A843)
                              : Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Scan QR',
                        style: TextStyle(
                          fontSize: 10,
                          color: _currentIndex == 2
                              ? const Color(0xFFD4A843)
                              : Colors.white54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              _navItem(
                icon: _navData[3].icon,
                label: _navData[3].label,
                index: 3,
              ),
              _navItem(
                icon: _navData[4].icon,
                label: _navData[4].label,
                index: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // APP BAR — name-based avatar (opens drawer) + live mobile
  // number pulled straight from FirebaseAuth. On tablet/desktop
  // the nav items (Home/Projects/Scan QR/Saved/Profile) are
  // rendered as app bar "actions", which Flutter automatically
  // right-aligns for us.
  // ==========================================================
  PreferredSizeWidget _buildAppBar({
    required bool useTopNav,
    required bool isDesktop,
  }) {
    final mobileNumber = _currentUser?.phoneNumber ?? 'Not linked';

    return AppBar(
      backgroundColor: const Color(0xFF080E13),
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 16,

      // Tablet/Desktop ko thoda extra height taaki icon+label nav
      // items comfortably fit ho jaayein.
      toolbarHeight: useTopNav ? 68 : kToolbarHeight,

      title: StreamBuilder<DatabaseEvent>(
        // FIX: `_userRef` is now a mutable field that gets reassigned
        // (via setState) once the real signed-in user is known, so this
        // StreamBuilder automatically resubscribes to the CORRECT path
        // instead of being stuck forever on `users/unknown`.
        stream: _userRef.onValue,
        builder: (context, snapshot) {
          String name = _currentUser?.displayName ?? '';
          String photoUrl = '';

          final value = snapshot.data?.snapshot.value;
          if (value != null && value is Map) {
            final map = Map<dynamic, dynamic>.from(value);
            final fetchedName = (map['name'] ?? '').toString();
            if (fetchedName.isNotEmpty) name = fetchedName;
            photoUrl = (map['photoUrl'] ?? '').toString();
          }

          final initial = name.trim().isNotEmpty
              ? name.trim()[0].toUpperCase()
              : 'U';

          return Row(
            children: [
              // Name-based avatar / placeholder icon -> opens the drawer.
              GestureDetector(
                onTap: () => _scaffoldKey.currentState?.openDrawer(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4A843),
                    shape: BoxShape.circle,
                    image: photoUrl.isNotEmpty
                        ? DecorationImage(
                      image: NetworkImage(photoUrl),
                      fit: BoxFit.cover,
                    )
                        : null,
                  ),
                  child: photoUrl.isEmpty
                      ? Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                      : null,
                ),
              ),
              const SizedBox(width: 12),

              // Name + live mobile number.
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name.isNotEmpty ? name : 'Welcome',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.phone_outlined,
                          size: 12,
                          color: Colors.white38,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          mobileNumber,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),

      // Tablet/Desktop: nav items right-aligned in the app bar.
      // Mobile: no actions (nav lives in the bottom bar instead).
      actions: useTopNav
          ? [
        for (int i = 0; i < _navData.length; i++)
          _topNavItem(
            icon: _navData[i].icon,
            label: _navData[i].label,
            index: i,
            compact: !isDesktop, // tablet par thoda tight spacing
          ),
        const SizedBox(width: 16),
      ]
          : null,
    );
  }

  // ==========================================================
  // TOP NAV ITEM — used only on tablet/desktop, rendered inside
  // AppBar's `actions` (which right-aligns automatically).
  // ==========================================================
  Widget _topNavItem({
    required IconData icon,
    required String label,
    required int index,
    required bool compact,
  }) {
    final bool selected = _currentIndex == index;
    final Color color = selected ? const Color(0xFFD4A843) : Colors.white60;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            setState(() {
              _currentIndex = index;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: color),
                if (!compact) ...[
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: color,
                      fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // BOTTOM NAV ITEM — used only on mobile.
  // ==========================================================
  Widget _navItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final bool selected = _currentIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _currentIndex = index;
          });
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: selected ? const Color(0xFFD4A843) : Colors.white54,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: selected ? const Color(0xFFD4A843) : Colors.white54,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Small data holder so bottom-bar and top-bar nav items always
// stay in sync (same icon/label per index).
class _NavData {
  final IconData icon;
  final String label;

  const _NavData({required this.icon, required this.label});
}