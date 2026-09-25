import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:visionar/screens/home/model_core.dart';

import 'package:visionar/services/saved_models_service.dart';
import 'package:visionar/screens/home/models_screen.dart';
import 'package:visionar/screens/home/Model%20detail%20screen.dart';
import 'package:visionar/screens/home/Home_Content.dart' show networkThumb;

/// ===================================================================
/// SAVED SCREEN
/// ===================================================================
/// Home / Discover screens ke kisi bhi model card par bookmark icon
/// tap karne se jo model IDs `SavedModelsService` me save hote hain,
/// wahi is screen par dikhte hain.
///
/// Poora ModelRecord yahan Firebase se hi (live) nikala jata hai -
/// sirf ID cache/persist hota hai - taaki agar admin panel se model
/// baad me edit/delete ho jaye to yeh screen hamesha latest data hi
/// dikhaye.
///
/// Har tile par ek filled bookmark icon hota hai - dobara tap karne se
/// model turant list se remove ho jata hai ("unsave"). Tile par tap
/// karne se seedha `ModelDetailScreen` khulti hai - Home/Discover ki
/// tarah hi.
/// ===================================================================

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  final DatabaseReference _modelsRef =
  FirebaseDatabase.instance.ref('models');

  @override
  void initState() {
    super.initState();
    // Agar app start par SavedModelsService.init() kahin aur (jaise
    // main.dart) se call nahi kiya gaya, to yahan bhi safe hai -
    // isSaved/toggleSave khud lazily load kar lete hain, lekin ek
    // explicit init yahan UI ko turant sahi state dikhane me madad
    // karta hai.
    SavedModelsService.instance.init();
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
          'Saved',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: AnimatedBuilder(
        // SaveButton kahin bhi (Home/Discover) tap hote hi yahan turant
        // rebuild hoga, kyunki yeh wahi shared service sun raha hai.
        animation: SavedModelsService.instance,
        builder: (context, _) {
          final savedIds = SavedModelsService.instance.savedIds;

          if (savedIds.isEmpty) {
            return _buildEmptyState();
          }

          return StreamBuilder<DatabaseEvent>(
            stream: _modelsRef.onValue,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFFD4A843)),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Firebase error: ${snapshot.error}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                );
              }

              final event = snapshot.data;
              final models = <ModelRecord>[];

              if (event != null) {
                for (final child in event.snapshot.children) {
                  final key = child.key;
                  if (key == null || !savedIds.contains(key)) continue;

                  try {
                    final model = ModelRecord.fromSnapshot(child);
                    if (model.modelUrl.trim().isNotEmpty) {
                      models.add(model);
                    }
                  } catch (_) {
                    // corrupt/invalid record - skip silently.
                  }
                }
              }

              models.sort((a, b) {
                final at = a.updatedAt > 0 ? a.updatedAt : a.createdAt;
                final bt = b.updatedAt > 0 ? b.updatedAt : b.createdAt;
                return bt.compareTo(at);
              });

              // Agar kisi saved ID ka model Firebase se delete ho chuka
              // ho, to wo yahan naturally list me nahi aayega. Us ID
              // par koi crash nahi hoga - bas empty state dikh jayega.
              if (models.isEmpty) {
                return _buildEmptyState();
              }

              return ListView.separated(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(20),
                itemCount: models.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  return _SavedTile(model: models[index]);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(25),
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF111920),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              color: Color(0xFFD4A843),
              size: 50,
            ),
            SizedBox(height: 15),
            Text(
              'No saved projects yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 7),
            Text(
              'Save projects you want to explore later.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedTile extends StatelessWidget {
  final ModelRecord model;

  const _SavedTile({required this.model});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ModelDetailScreen(model: model),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF151C24),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(12),
                ),
                child: SizedBox(
                  width: 96,
                  height: 90,
                  child: networkThumb(model.thumbnailUrl),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        model.modelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        model.description?.trim().isNotEmpty == true
                            ? model.description!.trim()
                            : 'No description',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Remove-from-saved button (always filled here, since
              // every tile on this screen is, by definition, saved).
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    SavedModelsService.instance.removeSave(model.id);
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.bookmark_rounded,
                      color: Color(0xFFD4A843),
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}