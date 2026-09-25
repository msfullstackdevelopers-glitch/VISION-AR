import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// NOTE: is file ko project me use karne se pehle pubspec.yaml me
// `shared_preferences` dependency add karein:
//
//   dependencies:
//     shared_preferences: ^2.2.2
//
// aur `flutter pub get` chala lein.

/// ===================================================================
/// SAVED MODELS SERVICE
/// ===================================================================
/// Chhota, app-wide singleton service jo "saved" (bookmarked) model
/// IDs ko device par persist karta hai (SharedPreferences ke zariye),
/// taaki app band/restart hone ke baad bhi saved list yaad rahe.
///
/// Ye sirf model IDs store karta hai - poora ModelRecord nahi - kyunki
/// asli/latest model data hamesha Firebase se hi aana chahiye. Agar
/// admin ne baad me model edit/delete kiya, SavedScreen turant naya
/// data dikhayega, purana cached data nahi.
///
/// Use karne ke tareeke:
///   SavedModelsService.instance.isSaved(id)      -> bool
///   SavedModelsService.instance.toggleSave(id)   -> save/unsave
///   SavedModelsService.instance.removeSave(id)   -> explicit unsave
///
/// UI ko changes par turant rebuild karne ke liye ye `ChangeNotifier`
/// extend karta hai. Neeche wala `SaveButton` widget isi service ko
/// `AnimatedBuilder` se listen karta hai, taaki jahan bhi ye button
/// use ho, save/unsave hote hi icon turant update ho jaye - Home,
/// Discover aur Saved screen teeno me ek saath.
/// ===================================================================

class SavedModelsService extends ChangeNotifier {
  SavedModelsService._internal();

  static final SavedModelsService instance = SavedModelsService._internal();

  static const String _prefsKey = 'saved_model_ids';

  final Set<String> _savedIds = {};
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  /// Currently saved model IDs (read-only snapshot).
  Set<String> get savedIds => Set.unmodifiable(_savedIds);

  /// App start hote hi (jaise main.dart me `WidgetsBinding` ke baad,
  /// ya kisi bhi screen ke `initState` me) ek baar call kar lein taaki
  /// disk se saved IDs load ho jayein. Agar kahin call nahi bhi kiya
  /// gaya, to `isSaved`/`toggleSave` khud lazily load kar lete hain.
  Future<void> init() async {
    if (_isLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _savedIds
            ..clear()
            ..addAll(decoded.map((e) => e.toString()));
        }
      }
    } catch (_) {
      // Corrupt/old prefs data - start fresh instead of crashing.
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  Future<void> _ensureLoaded() async {
    if (!_isLoaded) await init();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_savedIds.toList()));
    } catch (_) {
      // Persist fail hone par bhi in-memory state is session ke liye
      // sahi rehta hai - silently ignore, jaise baaki app me hota hai.
    }
  }

  bool isSaved(String modelId) {
    if (modelId.isEmpty) return false;
    return _savedIds.contains(modelId);
  }

  /// Save/unsave toggle karta hai, turant UI ko notify karta hai, aur
  /// background me disk par persist bhi kar deta hai.
  Future<void> toggleSave(String modelId) async {
    if (modelId.isEmpty) return;
    await _ensureLoaded();

    if (_savedIds.contains(modelId)) {
      _savedIds.remove(modelId);
    } else {
      _savedIds.add(modelId);
    }

    notifyListeners();
    await _persist();
  }

  /// SavedScreen ke "remove" button ke liye - explicit unsave
  /// (idempotent: already-unsaved id par kuch nahi hota).
  Future<void> removeSave(String modelId) async {
    if (modelId.isEmpty) return;
    await _ensureLoaded();
    if (_savedIds.remove(modelId)) {
      notifyListeners();
      await _persist();
    }
  }
}

/// ===================================================================
/// SAVE BUTTON (shared widget)
/// ===================================================================
/// Chhota bookmark icon button - kisi bhi model card ke corner me
/// overlay ki tarah use karo. Tap karte hi save/unsave toggle hota hai
/// aur icon turant (filled <-> outline) update ho jata hai. Ye button
/// khud apna listener AnimatedBuilder se lagata hai, isliye ise use
/// karne wale parent widget ko kuch alag se StatefulWidget banane ki
/// zaroorat nahi.
/// ===================================================================

class SaveButton extends StatelessWidget {
  final String modelId;
  final double size;
  final Color activeColor;
  final Color inactiveColor;
  final Color backgroundColor;

  const SaveButton({
    super.key,
    required this.modelId,
    this.size = 18,
    this.activeColor = const Color(0xFFD4A843),
    this.inactiveColor = Colors.white,
    this.backgroundColor = const Color(0xB3000000), // black @ ~70% opacity
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SavedModelsService.instance,
      builder: (context, _) {
        final saved = SavedModelsService.instance.isSaved(modelId);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            SavedModelsService.instance.toggleSave(modelId);
          },
          child: Container(
            width: size + 16,
            height: size + 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: saved ? activeColor : inactiveColor,
              size: size,
            ),
          ),
        );
      },
    );
  }
}