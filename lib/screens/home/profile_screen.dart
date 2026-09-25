import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../login_screen.dart';

// ============================================================
// RESPONSIVE HELPERS
// ============================================================
//
// Simple breakpoint based device classification used to adapt
// paddings, font sizes, avatar sizes and max content width for
// mobile / tablet / desktop without changing any business logic.
// ============================================================

enum DeviceType { mobile, tablet, desktop }

DeviceType deviceTypeOf(double width) {
  if (width >= 1000) return DeviceType.desktop;
  if (width >= 650) return DeviceType.tablet;
  return DeviceType.mobile;
}

extension DeviceTypeX on DeviceType {
  bool get isMobile => this == DeviceType.mobile;
  bool get isTablet => this == DeviceType.tablet;
  bool get isDesktop => this == DeviceType.desktop;
}

// ============================================================
// MODEL — user profile data structure (Realtime DB <-> Dart)
// ============================================================
class UserProfileModel {
  final String uid;
  final String name;
  final String username;
  final String email;
  final String phoneNumber;
  final String photoUrl;

  UserProfileModel({
    required this.uid,
    this.name = '',
    this.username = '',
    this.email = '',
    this.phoneNumber = '',
    this.photoUrl = '',
  });

  factory UserProfileModel.fromMap(Map<dynamic, dynamic> map, String uid) {
    return UserProfileModel(
      uid: uid,
      name: map['name'] ?? '',
      username: map['username'] ?? '',
      email: map['email'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      photoUrl: map['photoUrl'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'username': username,
      'email': email,
      'phoneNumber': phoneNumber,
      'photoUrl': photoUrl,
    };
  }

  UserProfileModel copyWith({
    String? name,
    String? username,
    String? email,
    String? phoneNumber,
    String? photoUrl,
  }) {
    return UserProfileModel(
      uid: uid,
      name: name ?? this.name,
      username: username ?? this.username,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }
}

// ============================================================
// SERVICE — Firebase Auth + Realtime Database + Storage logic
// ============================================================
class ProfileService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  User? get currentUser => _auth.currentUser;

  // Realtime Database reference: users/{uid}
  DatabaseReference _userRef(String uid) => _db.ref('users/$uid');

  /// Live stream so ProfileScreen auto-updates after saving edits.
  ///
  /// IMPORTANT FIX: this used to read `currentUser` directly and
  /// `throw Exception(...)` the moment it was called if the user was
  /// briefly null (e.g. right after a hot refresh on Flutter Web,
  /// or before FirebaseAuth finishes restoring the session). Because
  /// that throw happened synchronously *outside* the stream (when the
  /// stream getter itself was called during build), StreamBuilder's
  /// `snapshot.hasError` could never catch it — it crashed the whole
  /// widget build instead, which is exactly what showed up as a
  /// "blank profile page".
  ///
  /// Now the stream is built on top of `authStateChanges()`, so it
  /// reacts to login/logout automatically, never throws synchronously,
  /// and any real database error becomes a normal stream error that
  /// the UI can show and let the user retry.
  Stream<UserProfileModel> profileStream() {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) {
        // No signed-in user right now — emit an "empty" profile
        // instead of throwing. The UI decides what to show.
        return Stream<UserProfileModel>.value(UserProfileModel(uid: ''));
      }

      return _userRef(user.uid).onValue.map((event) {
        final data = event.snapshot.value;

        if (data == null || data is! Map) {
          return UserProfileModel(
            uid: user.uid,
            phoneNumber: user.phoneNumber ?? '',
            email: user.email ?? '',
          );
        }

        final model = UserProfileModel.fromMap(
          Map<dynamic, dynamic>.from(data),
          user.uid,
        );
        // Mobile number is always trusted from FirebaseAuth (verified source).
        return model.copyWith(phoneNumber: user.phoneNumber ?? '');
      });
    });
  }

  /// One-time fetch, used to pre-fill the Edit form.
  Future<UserProfileModel> fetchProfileOnce() async {
    final uid = currentUser?.uid;
    if (uid == null) throw Exception('No logged in user found.');

    final snapshot = await _userRef(uid).get();
    final phoneFromAuth = currentUser?.phoneNumber ?? '';

    if (!snapshot.exists || snapshot.value == null) {
      return UserProfileModel(
        uid: uid,
        phoneNumber: phoneFromAuth,
        email: currentUser?.email ?? '',
      );
    }

    final model = UserProfileModel.fromMap(
      Map<dynamic, dynamic>.from(snapshot.value as Map),
      uid,
    );
    return model.copyWith(phoneNumber: phoneFromAuth);
  }

  /// Uploads picked image to Firebase Storage, returns download URL.
  Future<String> uploadProfileImage(File imageFile) async {
    final uid = currentUser?.uid;
    if (uid == null) throw Exception('No logged in user found.');

    final ref = _storage.ref().child('profile_images').child('$uid.jpg');
    final uploadTask = await ref.putFile(imageFile);
    return await uploadTask.ref.getDownloadURL();
  }

  /// Saves name, username, email, photoUrl to Realtime Database.
  /// Uses `update()` so only these fields change, nothing else is
  /// overwritten (equivalent to Firestore's `set(merge: true)`).
  Future<void> saveProfile({
    required String name,
    required String username,
    required String email,
    String? photoUrl,
  }) async {
    final uid = currentUser?.uid;
    if (uid == null) throw Exception('No logged in user found.');

    final data = <String, dynamic>{
      'name': name.trim(),
      'username': username.trim(),
      'email': email.trim(),
      'phoneNumber': currentUser?.phoneNumber ?? '',
    };

    if (photoUrl != null) {
      data['photoUrl'] = photoUrl;
    }

    await _userRef(uid).update(data);

    // Keep FirebaseAuth's own email field in sync too.
    // Throws `requires-recent-login` if the session is old —
    // in that case ask the user to re-login and try again.
    if (email.trim().isNotEmpty && email.trim() != currentUser?.email) {
      await currentUser?.verifyBeforeUpdateEmail(email.trim());
    }
  }

  Future<void> logOut() async {
    await _auth.signOut();
  }
}

// ============================================================
// PROFILE SCREEN — shows live data from Realtime DB + Auth
// ============================================================
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ProfileService _service = ProfileService();

  // FIX: build a single, stable stream once (in initState) instead of
  // calling `_service.profileStream()` fresh on every StreamBuilder
  // rebuild inside build(). Re-creating the stream on every build was
  // wasteful and made the "blank page" race condition worse.
  late Stream<UserProfileModel> _profileStream;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _profileStream = _service.profileStream();
  }

  void _retry() {
    setState(() {
      _profileStream = _service.profileStream();
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirmLogOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111920),
        title: const Text('Log Out', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to log out?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (_loggingOut) return; // guard against double taps

    setState(() => _loggingOut = true);

    try {
      await _service.logOut();
    } catch (e) {
      debugPrint('DEBUG: logOut failed -> $e');
      if (mounted) {
        setState(() => _loggingOut = false);
        _showSnack('Log out failed: $e');
      }
      return;
    }

    if (!mounted) return;

    // FIX: the old code called
    //   Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    // but this app does NOT navigate with named routes anywhere else
    // (Login/OTP/Home all use MaterialPageRoute directly). If '/login'
    // was never registered in MaterialApp's `routes`, this call throws
    // and the button silently does nothing — which is exactly the bug
    // that was reported. Using MaterialPageRoute matches the pattern
    // used everywhere else in the app (see LoginScreen -> HomeScreen)
    // and always works regardless of whether named routes exist.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070D12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070D12),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: StreamBuilder<UserProfileModel>(
        stream: _profileStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFD4A843)),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Colors.white38, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      'Something went wrong: ${snapshot.error}',
                      style: const TextStyle(color: Colors.white54),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _retry,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD4A843),
                        side: const BorderSide(color: Color(0xFFD4A843)),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final profile = snapshot.data;

          // FIX: previously a null/missing user silently fell back to
          // `UserProfileModel(uid: _service.currentUser?.uid ?? '')`
          // and just rendered as if everything was fine, with empty
          // fields — which is one of the ways the page could look
          // "blank". Now we detect "no signed-in user" explicitly and
          // show a clear screen with a way back to Login, instead of
          // an empty-looking profile.
          if (profile == null || profile.uid.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_off_outlined,
                        color: Colors.white38, size: 40),
                    const SizedBox(height: 12),
                    const Text(
                      'You are not logged in.',
                      style: TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                              (route) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4A843),
                      ),
                      child: const Text(
                        'Go to Login',
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final deviceType = deviceTypeOf(constraints.maxWidth);

              // Content max width & horizontal padding scale up on
              // wider screens so the card doesn't stretch edge to edge.
              final maxContentWidth = switch (deviceType) {
                DeviceType.mobile => double.infinity,
                DeviceType.tablet => 560.0,
                DeviceType.desktop => 640.0,
              };

              final horizontalPadding = switch (deviceType) {
                DeviceType.mobile => 20.0,
                DeviceType.tablet => 32.0,
                DeviceType.desktop => 40.0,
              };

              final avatarSize = switch (deviceType) {
                DeviceType.mobile => 82.0,
                DeviceType.tablet => 96.0,
                DeviceType.desktop => 108.0,
              };

              final nameFontSize = switch (deviceType) {
                DeviceType.mobile => 20.0,
                DeviceType.tablet => 22.0,
                DeviceType.desktop => 24.0,
              };

              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: ListView(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: 20,
                    ),
                    children: [
                      const SizedBox(height: 10),

                      Center(
                        child: Container(
                          width: avatarSize,
                          height: avatarSize,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4A843),
                            shape: BoxShape.circle,
                            image: profile.photoUrl.isNotEmpty
                                ? DecorationImage(
                              image: NetworkImage(profile.photoUrl),
                              fit: BoxFit.cover,
                            )
                                : null,
                          ),
                          child: profile.photoUrl.isEmpty
                              ? Icon(
                            Icons.person_rounded,
                            color: Colors.black,
                            size: avatarSize * 0.55,
                          )
                              : null,
                        ),
                      ),

                      const SizedBox(height: 14),

                      Center(
                        child: Text(
                          profile.name.isNotEmpty
                              ? profile.name
                              : 'Add your name',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: nameFontSize,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),

                      const SizedBox(height: 5),

                      Center(
                        child: Text(
                          profile.username.isNotEmpty
                              ? '@${profile.username}'
                              : 'Welcome to VISIONAR',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ---- Contact info card: mobile number + email ----
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111920),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            _infoRow(
                              Icons.phone_outlined,
                              'Mobile Number',
                              profile.phoneNumber.isNotEmpty
                                  ? profile.phoneNumber
                                  : 'Not linked',
                            ),
                            const Divider(color: Colors.white10, height: 1),
                            _infoRow(
                              Icons.email_outlined,
                              'Email',
                              profile.email.isNotEmpty
                                  ? profile.email
                                  : 'Not added',
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      _item(
                        Icons.person_outline_rounded,
                        'Edit Profile',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const EditProfileScreen(),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      GestureDetector(
                        onTap: _loggingOut ? null : _confirmLogOut,
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.red.withOpacity(0.25),
                            ),
                          ),
                          child: Center(
                            child: _loggingOut
                                ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.redAccent,
                                ),
                              ),
                            )
                                : const Text(
                              'Log Out',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white30, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(IconData icon, String title, {VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111920),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: Colors.white70),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          color: Colors.white30,
          size: 15,
        ),
      ),
    );
  }
}

// ============================================================
// EDIT PROFILE SCREEN — edit name, username, email, photo
// ============================================================
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = ProfileService();

  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();

  String _existingPhotoUrl = '';
  String _phoneNumber = '';
  File? _pickedImage;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadCurrentData();
  }

  Future<void> _loadCurrentData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final profile = await _service.fetchProfileOnce();
      _nameController.text = profile.name;
      _usernameController.text = profile.username;
      _emailController.text = profile.email;
      _existingPhotoUrl = profile.photoUrl;
      _phoneNumber = profile.phoneNumber;
    } catch (e) {
      debugPrint('DEBUG: fetchProfileOnce failed -> $e');
      _loadError = 'Failed to load profile: $e';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 800,
    );
    if (picked != null) {
      setState(() => _pickedImage = File(picked.path));
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      String? photoUrl;
      if (_pickedImage != null) {
        photoUrl = await _service.uploadProfileImage(_pickedImage!);
      }

      await _service.saveProfile(
        name: _nameController.text,
        username: _usernameController.text,
        email: _emailController.text,
        photoUrl: photoUrl,
      );

      if (mounted) {
        _showSnack('Profile updated successfully');
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('DEBUG: saveProfile failed -> $e');
      _showSnack('Failed to save profile: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070D12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070D12),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Edit Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(color: Color(0xFFD4A843)),
      )
          : _loadError != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _loadError!,
                style: const TextStyle(color: Colors.white54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _loadCurrentData,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD4A843),
                  side: const BorderSide(color: Color(0xFFD4A843)),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      )
          : LayoutBuilder(
        builder: (context, constraints) {
          final deviceType = deviceTypeOf(constraints.maxWidth);

          final maxContentWidth = switch (deviceType) {
            DeviceType.mobile => double.infinity,
            DeviceType.tablet => 560.0,
            DeviceType.desktop => 640.0,
          };

          final horizontalPadding = switch (deviceType) {
            DeviceType.mobile => 20.0,
            DeviceType.tablet => 32.0,
            DeviceType.desktop => 40.0,
          };

          final avatarSize = switch (deviceType) {
            DeviceType.mobile => 92.0,
            DeviceType.tablet => 104.0,
            DeviceType.desktop => 116.0,
          };

          // On desktop/tablet, form fields sit two-per-row so the
          // form doesn't look like a single stretched-out column.
          final useTwoColumnFields = !deviceType.isMobile;

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: 20,
                  ),
                  children: [
                    const SizedBox(height: 10),
                    Center(
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: Stack(
                          children: [
                            _buildAvatar(avatarSize),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFD4A843),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.camera_alt_rounded,
                                  size: 16,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    if (useTwoColumnFields)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                _label('Full Name'),
                                _buildTextField(
                                  controller: _nameController,
                                  hint: 'Enter your name',
                                  icon: Icons.person_outline_rounded,
                                  validator: (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Name is required'
                                      : null,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                _label('Username'),
                                _buildTextField(
                                  controller: _usernameController,
                                  hint: 'Enter your username',
                                  icon:
                                  Icons.alternate_email_rounded,
                                  validator: (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Username is required'
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _label('Full Name'),
                      _buildTextField(
                        controller: _nameController,
                        hint: 'Enter your name',
                        icon: Icons.person_outline_rounded,
                        validator: (v) =>
                        (v == null || v.trim().isEmpty)
                            ? 'Name is required'
                            : null,
                      ),
                      const SizedBox(height: 18),
                      _label('Username'),
                      _buildTextField(
                        controller: _usernameController,
                        hint: 'Enter your username',
                        icon: Icons.alternate_email_rounded,
                        validator: (v) =>
                        (v == null || v.trim().isEmpty)
                            ? 'Username is required'
                            : null,
                      ),
                    ],
                    const SizedBox(height: 18),

                    _label('Email'),
                    _buildTextField(
                      controller: _emailController,
                      hint: 'Enter your email',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Email is required';
                        }
                        final emailRegex = RegExp(
                            r'^[\w.\-]+@([\w\-]+\.)+[\w\-]{2,}$');
                        if (!emailRegex.hasMatch(v.trim())) {
                          return 'Enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),

                    _label('Mobile Number'),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111920),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.phone_outlined,
                            color: Colors.white38,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _phoneNumber.isEmpty
                                ? 'Not linked'
                                : _phoneNumber,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          const Icon(
                            Icons.lock_outline_rounded,
                            color: Colors.white24,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Text(
                        'Mobile number is verified via login and cannot be edited here.',
                        style: TextStyle(
                            color: Colors.white30, fontSize: 11),
                      ),
                    ),

                    const SizedBox(height: 34),

                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD4A843),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.black,
                          ),
                        )
                            : const Text(
                          'Save Changes',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAvatar(double size) {
    ImageProvider? imageProvider;
    if (_pickedImage != null) {
      imageProvider = FileImage(_pickedImage!);
    } else if (_existingPhotoUrl.isNotEmpty) {
      imageProvider = NetworkImage(_existingPhotoUrl);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFD4A843),
        shape: BoxShape.circle,
        image: imageProvider != null
            ? DecorationImage(image: imageProvider, fit: BoxFit.cover)
            : null,
      ),
      child: imageProvider == null
          ? Icon(Icons.person_rounded, color: Colors.black, size: size * 0.52)
          : null,
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111920),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.white38, size: 20),
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
          border: InputBorder.none,
          errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 11),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}