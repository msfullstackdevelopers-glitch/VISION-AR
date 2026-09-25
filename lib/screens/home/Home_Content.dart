import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:visionar/screens/home/Model%20detail%20screen.dart';
import 'package:visionar/screens/home/discover_screen.dart';
import 'package:visionar/screens/home/model_core.dart';
import 'package:visionar/screens/home/models_screen.dart';
import 'package:visionar/services/saved_models_service.dart';

// TODO: Adjust these imports according to the actual paths in your project.
// models_screen.dart should contain the ModelRecord and ModelFullViewScreen classes,
// and model_detail_screen.dart should contain the ModelDetailScreen class.
// Both files are expected to already exist in the project.

/// ===================================================================
/// RESPONSIVE BREAKPOINTS
/// ===================================================================
/// Same breakpoints used across the app (Login/OTP/Splash/HomeScreen):
///   - width <  650  -> mobile
///   - 650 <= width < 1100 -> tablet
///   - width >= 1100 -> desktop
///
/// Every layout-affecting piece of this screen (paddings, font sizes,
/// card sizes, how many "Recommended" cards are visible at once, and
/// whether the "Optional" / category-list models render as a
/// horizontal scroller or a grid) branches off this single enum so the
/// three form-factors can be tuned independently without duplicating
/// business logic (Firebase parsing/sorting stays 100% shared).
///
/// NOTE: On desktop the content now stretches to the full available
/// width (minus the horizontal padding) instead of being centered
/// inside a fixed max-width column. This removes the empty gutters
/// that used to appear on the left/right when the browser window was
/// maximized / full-screened.
/// ===================================================================
enum DeviceType { mobile, tablet, desktop }

DeviceType _deviceTypeOf(double width) {
  if (width >= 1100) return DeviceType.desktop;
  if (width >= 650) return DeviceType.tablet;
  return DeviceType.mobile;
}

extension _DeviceTypeX on DeviceType {
  bool get isMobile => this == DeviceType.mobile;
  bool get isTablet => this == DeviceType.tablet;
  bool get isDesktop => this == DeviceType.desktop;
}

/// ===================================================================
/// HOME CONTENT
/// ===================================================================
/// Models uploaded or updated from the admin panel include a `category`
/// field (Recommended / Govt / My Project / Discover / Optional).
/// This screen reads those categories live from Firebase Realtime Database:
///
///   - "Recommended for You" -> category == "Recommended". These models
///     appear in an auto-sliding carousel that advances every second.
///     Tapping a card first opens ModelDetailScreen with the thumbnail,
///     media, details, and the "Open 3D Model" button. From there,
///     ModelFullViewScreen can be opened.
///   - Government / My Projects cards -> tapping a card opens the complete
///     category list with a search bar in CategoryModelsScreen. Tapping any
///     list tile opens ModelDetailScreen first.
///   - Discover card -> navigates directly to `DiscoverScreen`.
///   - The project-card row at the bottom -> shows real models where
///     category == "Optional" in a horizontal list (grid on tablet/desktop).
///     Tapping a card opens ModelDetailScreen.
///
/// Every model card in the Recommended slider, Optional row, and category
/// list tiles for Govt/My Project includes a bookmark/save icon. Tapping it
/// saves the model through `SavedModelsService`; tapping again removes it.
/// The shared service keeps the SavedScreen in sync. Tapping anywhere else
/// on the card continues to open ModelDetailScreen.
///
/// A white, bold "Experience the Future" heading is displayed directly
/// above the Govt/My Projects/Discover card row.
///
/// RESPONSIVE: Mobile keeps the original single-column phone layout.
/// Tablet widens paddings/cards and shows 2 Recommended cards at once.
/// Desktop shows 3 Recommended cards at once, renders the Optional row
/// as a grid instead of a horizontal scroller, and now fills the full
/// browser width (no more centered max-width column with empty side
/// gutters).
/// ===================================================================

class HomeContent extends StatefulWidget {
  const HomeContent({super.key});

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  final DatabaseReference _modelsRef =
  FirebaseDatabase.instance.ref('models');

  @override
  void initState() {
    super.initState();
    // Load saved IDs from local storage once so bookmark icons show the
    // correct filled/outline state from the first build.
    SavedModelsService.instance.init();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final deviceType = _deviceTypeOf(constraints.maxWidth);

          return StreamBuilder<DatabaseEvent>(
            stream: _modelsRef.onValue,
            builder: (context, snapshot) {
              final allModels = _parseModels(snapshot);

              final recommended = allModels
                  .where((m) => m.category == 'Recommended')
                  .toList();

              final optional =
              allModels.where((m) => m.category == 'Optional').toList();

              final horizontalPadding = switch (deviceType) {
                DeviceType.mobile => 20.0,
                DeviceType.tablet => 32.0,
                DeviceType.desktop => 48.0,
              };

              final content = Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  14,
                  horizontalPadding,
                  25,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: deviceType.isMobile ? 22 : 12),
                    _buildHeroHeading(deviceType),
                    const SizedBox(height: 18),
                    _buildCategoryCardsRow(context, deviceType),
                    const SizedBox(height: 23),
                    _buildRecommendedHeader(context, deviceType),
                    const SizedBox(height: 12),
                    _RecommendedSlider(
                      models: recommended,
                      deviceType: deviceType,
                    ),
                    const SizedBox(height: 23),
                    Text(
                      'Explore More',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: deviceType.isMobile ? 16 : 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _OptionalModelsRow(
                      models: optional,
                      deviceType: deviceType,
                    ),
                  ],
                ),
              );

              // Content now always stretches to fill the available
              // width (the horizontalPadding above already keeps text
              // and cards off the very edge of the screen). No more
              // Center + ConstrainedBox(maxWidth: 1280) wrapper, so
              // full-screen desktop windows no longer show empty
              // gutters on the left/right.
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: content,
              );
            },
          );
        },
      ),
    );
  }

  /// White, bold, italic heading shown directly above the
  /// Govt/My Projects/Discover cards. Scales up slightly on
  /// larger screens so it doesn't look lost in the extra width.
  Widget _buildHeroHeading(DeviceType deviceType) {
    final fontSize = switch (deviceType) {
      DeviceType.mobile => 22.0,
      DeviceType.tablet => 26.0,
      DeviceType.desktop => 30.0,
    };

    return Text(
      'Experience the Future',
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        fontStyle: FontStyle.italic,
        letterSpacing: 0.2,
      ),
    );
  }

  /// Converts a Realtime Database snapshot into a ModelRecord list.
  /// Parsing follows the same approach as ModelsScreen and skips invalid entries.
  List<ModelRecord> _parseModels(AsyncSnapshot<DatabaseEvent> snapshot) {
    final event = snapshot.data;
    if (event == null) return const [];

    final models = <ModelRecord>[];

    for (final child in event.snapshot.children) {
      try {
        final model = ModelRecord.fromSnapshot(child);
        if (model.modelUrl.trim().isNotEmpty) {
          models.add(model);
        }
      } catch (_) {
        // Corrupt or invalid record - skip silently.
      }
    }

    models.sort((a, b) {
      final at = a.updatedAt > 0 ? a.updatedAt : a.createdAt;
      final bt = b.updatedAt > 0 ? b.updatedAt : b.createdAt;
      return bt.compareTo(at);
    });

    return models;
  }

  Widget _buildCategoryCardsRow(BuildContext context, DeviceType deviceType) {
    final height = switch (deviceType) {
      DeviceType.mobile => 132.0,
      DeviceType.tablet => 150.0,
      DeviceType.desktop => 168.0,
    };
    final spacing = deviceType.isMobile ? 10.0 : 16.0;

    return SizedBox(
      height: height,
      child: Row(
        children: [
          _categoryCard(
            context: context,
            deviceType: deviceType,
            icon: Icons.account_balance_rounded,
            title: 'Government',
            subtitle: 'State Projects',
            iconColor: const Color(0xFFD4A843),
            category: 'Govt',
          ),
          SizedBox(width: spacing),
          _categoryCard(
            context: context,
            deviceType: deviceType,
            icon: Icons.bookmark_border_rounded,
            title: 'My Projects',
            subtitle: 'Shared & Saved',
            iconColor: const Color(0xFF4B8CCB),
            category: 'My Project',
          ),
          SizedBox(width: spacing),
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DiscoverScreen()),
                );
              },
              child: Container(
                padding: EdgeInsets.all(deviceType.isMobile ? 11 : 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111920),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: Colors.white.withOpacity(0.04)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.explore_outlined,
                      color: const Color(0xFF83C85C),
                      size: deviceType.isMobile ? 37 : 46,
                    ),
                    const SizedBox(height: 9),
                    Text(
                      'Discover',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: deviceType.isMobile ? 12 : 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Explore Projects',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: deviceType.isMobile ? 9 : 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the selected category list with a search bar when tapped.
  Widget _categoryCard({
    required BuildContext context,
    required DeviceType deviceType,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required String category,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CategoryModelsScreen(category: category),
            ),
          );
        },
        child: Container(
          padding: EdgeInsets.all(deviceType.isMobile ? 11 : 16),
          decoration: BoxDecoration(
            color: const Color(0xFF111920),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withOpacity(0.04)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: iconColor, size: deviceType.isMobile ? 37 : 46),
              const SizedBox(height: 9),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: deviceType.isMobile ? 12 : 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: deviceType.isMobile ? 9 : 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendedHeader(BuildContext context, DeviceType deviceType) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Recommended for You',
          style: TextStyle(
            color: Colors.white,
            fontSize: deviceType.isMobile ? 16 : 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiscoverScreen()),
            );
          },
          child: Text(
            'View All',
            style: TextStyle(
              color: const Color(0xFFD4A843),
              fontSize: deviceType.isMobile ? 13 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// ===================================================================
/// RECOMMENDED SLIDER (category == "Recommended")
/// ===================================================================
/// Mobile: one full-width card per page (unchanged from before).
/// Tablet: viewportFraction shows 2 cards at a time.
/// Desktop: viewportFraction shows 3 cards at a time.
/// Auto-slide still advances one page per second on every form factor.
/// ===================================================================

class _RecommendedSlider extends StatefulWidget {
  final List<ModelRecord> models;
  final DeviceType deviceType;

  const _RecommendedSlider({
    required this.models,
    required this.deviceType,
  });

  @override
  State<_RecommendedSlider> createState() => _RecommendedSliderState();
}

class _RecommendedSliderState extends State<_RecommendedSlider> {
  late PageController _pageController;
  Timer? _timer;
  int _currentPage = 0;
  double _appliedFraction = 1.0;

  /// How many cards we'd *like* to show side-by-side at once on this
  /// form factor, given enough models to fill them.
  int get _desiredVisibleCount => switch (widget.deviceType) {
    DeviceType.mobile => 1,
    DeviceType.tablet => 2,
    DeviceType.desktop => 3,
  };

  /// Actual viewport fraction, capped by how many models we actually
  /// have. E.g. on desktop with just 1 recommended model, the card
  /// fills the full width instead of sitting small with empty space
  /// beside it; with 2 models it splits the row in half; 3+ models
  /// falls back to the normal partial-peek carousel.
  double get _viewportFraction {
    final visible = widget.models.isEmpty
        ? 1
        : _desiredVisibleCount.clamp(1, widget.models.length);
    return 1 / visible;
  }

  double get _height => switch (widget.deviceType) {
    DeviceType.mobile => 178.0,
    DeviceType.tablet => 230.0,
    DeviceType.desktop => 280.0,
  };

  @override
  void initState() {
    super.initState();
    _appliedFraction = _viewportFraction;
    _pageController = PageController(viewportFraction: _appliedFraction);
    _startAutoSlide();
  }

  @override
  void didUpdateWidget(covariant _RecommendedSlider oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newFraction = _viewportFraction;
    final fractionChanged = (newFraction - _appliedFraction).abs() > 0.001;

    if (fractionChanged) {
      final oldPage = _currentPage;
      _appliedFraction = newFraction;
      _pageController.dispose();
      _pageController = PageController(
        viewportFraction: _appliedFraction,
        initialPage: oldPage,
      );
    }

    if (oldWidget.models.length != widget.models.length) {
      _currentPage = 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }

    if (fractionChanged || oldWidget.models.length != widget.models.length) {
      _startAutoSlide();
    }
  }

  void _startAutoSlide() {
    _timer?.cancel();

    if (widget.models.length <= 1) return;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_pageController.hasClients || widget.models.isEmpty) {
        return;
      }

      _currentPage = (_currentPage + 1) % widget.models.length;

      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.models.isEmpty) {
      return Container(
        height: _height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF111920),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.04)),
        ),
        child: const Text(
          'No recommended models are available yet',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      );
    }

    final cardGap = widget.deviceType.isMobile ? 2.0 : 8.0;

    return SizedBox(
      height: _height,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.models.length,
            onPageChanged: (index) {
              _currentPage = index;
            },
            itemBuilder: (context, index) {
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: cardGap),
                child: _RecommendedCard(model: widget.models[index]),
              );
            },
          ),
          if (widget.models.length > 1)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.models.length, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: index == _currentPage ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: index == _currentPage
                          ? const Color(0xFFD4A843)
                          : Colors.white38,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecommendedCard extends StatelessWidget {
  final ModelRecord model;

  const _RecommendedCard({required this.model});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ModelDetailScreen(model: model),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            networkThumb(model.thumbnailUrl, icon: Icons.view_in_ar),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.82),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 15,
              right: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.modelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    model.description?.trim().isNotEmpty == true
                        ? model.description!.trim()
                        : '3D Walkthrough',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            // Save/unsave bookmark icon, top-right corner.
            Positioned(
              top: 10,
              right: 10,
              child: SaveButton(modelId: model.id, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===================================================================
/// OPTIONAL MODELS ROW (category == "Optional")
/// ===================================================================
/// Mobile: horizontal scrolling list of fixed-width cards (unchanged).
/// Tablet/Desktop: a non-scrolling grid so the extra width is used
/// instead of leaving cards to scroll off-screen.
/// ===================================================================

class _OptionalModelsRow extends StatelessWidget {
  final List<ModelRecord> models;
  final DeviceType deviceType;

  const _OptionalModelsRow({
    required this.models,
    required this.deviceType,
  });

  @override
  Widget build(BuildContext context) {
    if (models.isEmpty) {
      return Container(
        height: 110,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF111920),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.04)),
        ),
        child: const Text(
          'No models are available yet',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      );
    }

    if (deviceType.isMobile) {
      return SizedBox(
        height: 110,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: models.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            return SizedBox(
              width: 165,
              child: _ProjectCard(model: models[index]),
            );
          },
        ),
      );
    }

    // Tablet/Desktop: fixed-height grid, laid out inline inside the
    // parent SingleChildScrollView (no nested scrolling). The column
    // count is capped by how many models we actually have, so 2-3
    // cards fill the row with larger cards instead of leaving a big
    // empty gap where the missing columns would have been.
    final desiredCrossAxisCount = deviceType.isTablet ? 3 : 4;
    final crossAxisCount = desiredCrossAxisCount.clamp(1, models.length);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: models.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: deviceType.isTablet ? 1.6 : 1.5,
      ),
      itemBuilder: (context, index) => _ProjectCard(model: models[index]),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final ModelRecord model;

  const _ProjectCard({required this.model});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ModelDetailScreen(model: model),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            networkThumb(model.thumbnailUrl, icon: Icons.view_in_ar),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.82)],
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 10,
              right: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.modelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    model.description?.trim().isNotEmpty == true
                        ? model.description!.trim()
                        : 'Optional',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 9),
                  ),
                ],
              ),
            ),
            // Save/unsave bookmark icon, top-right corner.
            Positioned(
              top: 8,
              right: 8,
              child: SaveButton(modelId: model.id, size: 15),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===================================================================
/// CATEGORY LIST SCREEN
/// ===================================================================
/// Mobile: vertical list of tiles (unchanged).
/// Tablet/Desktop: a responsive grid of the same tile content. The
/// search bar/content now stretches the full available width on
/// desktop too (no more centered max-width column with empty side
/// gutters).
/// ===================================================================

class CategoryModelsScreen extends StatefulWidget {
  final String category;

  const CategoryModelsScreen({super.key, required this.category});

  @override
  State<CategoryModelsScreen> createState() => _CategoryModelsScreenState();
}

class _CategoryModelsScreenState extends State<CategoryModelsScreen> {
  final DatabaseReference _modelsRef =
  FirebaseDatabase.instance.ref('models');
  final TextEditingController _searchController = TextEditingController();

  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F14),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.category,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final deviceType = _deviceTypeOf(constraints.maxWidth);
            final horizontalPadding = switch (deviceType) {
              DeviceType.mobile => 16.0,
              DeviceType.tablet => 32.0,
              DeviceType.desktop => 48.0,
            };

            // Full-width body (no Center + ConstrainedBox wrapper), so
            // the search bar and grid stretch edge-to-edge (minus
            // padding) on desktop instead of leaving empty gutters.
            return Padding(
              padding:
              EdgeInsets.fromLTRB(horizontalPadding, 10, horizontalPadding, 0),
              child: Column(
                children: [
                  // ---- SEARCH BAR ------------------------------------
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF121A21),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: Colors.white.withOpacity(0.04)),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 15),
                        const Icon(
                          Icons.search_rounded,
                          color: Colors.white54,
                          size: 23,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            cursorColor: const Color(0xFFD4A843),
                            decoration: const InputDecoration(
                              hintText: 'Search projects, locations...',
                              hintStyle: TextStyle(
                                color: Colors.white38,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                            ),
                            onChanged: (value) {
                              setState(() {
                                _search = value.trim().toLowerCase();
                              });
                            },
                          ),
                        ),
                        if (_search.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _search = '');
                            },
                            child: const Padding(
                              padding: EdgeInsets.only(right: 12),
                              child: Icon(
                                Icons.close_rounded,
                                color: Colors.white38,
                                size: 20,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ---- LIST / GRID ------------------------------------
                  Expanded(
                    child: StreamBuilder<DatabaseEvent>(
                      stream: _modelsRef.onValue,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child:
                            CircularProgressIndicator(color: Colors.white),
                          );
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'Firebase error: ${snapshot.error}',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          );
                        }

                        final event = snapshot.data;
                        final models = <ModelRecord>[];

                        if (event != null) {
                          for (final child in event.snapshot.children) {
                            try {
                              final model = ModelRecord.fromSnapshot(child);

                              if (model.modelUrl.trim().isEmpty) continue;
                              if (model.category != widget.category) continue;

                              if (_search.isNotEmpty) {
                                final name = model.modelName.toLowerCase();
                                final desc =
                                (model.description ?? '').toLowerCase();
                                final file =
                                (model.fileName ?? '').toLowerCase();

                                final matches = name.contains(_search) ||
                                    desc.contains(_search) ||
                                    file.contains(_search);

                                if (!matches) continue;
                              }

                              models.add(model);
                            } catch (_) {
                              // Corrupt record - skip
                            }
                          }
                        }

                        models.sort((a, b) {
                          final at =
                          a.updatedAt > 0 ? a.updatedAt : a.createdAt;
                          final bt =
                          b.updatedAt > 0 ? b.updatedAt : b.createdAt;
                          return bt.compareTo(at);
                        });

                        if (models.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.view_in_ar_outlined,
                                  color: Colors.white24,
                                  size: 46,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _search.isNotEmpty
                                      ? 'No models matched your search'
                                      : 'No models are available in ${widget.category} yet',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        if (deviceType.isMobile) {
                          return ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 20),
                            itemCount: models.length,
                            separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              return _CategoryListTile(model: models[index]);
                            },
                          );
                        }

                        // Tablet/Desktop: same tile content, arranged as
                        // a grid so wide screens show more at once.
                        // Desktop now uses more columns since the grid
                        // stretches the full window width.
                        final crossAxisCount = deviceType.isTablet ? 2 : 4;

                        return GridView.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 20),
                          itemCount: models.length,
                          gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: deviceType.isTablet ? 2.6 : 2.2,
                          ),
                          itemBuilder: (context, index) {
                            return _CategoryListTile(model: models[index]);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CategoryListTile extends StatelessWidget {
  final ModelRecord model;

  const _CategoryListTile({required this.model});

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
                      if (model.media.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.photo_library_outlined,
                              color: Colors.white38,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${model.media.length}',
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Save/unsave bookmark icon before the chevron.
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: SaveButton(
                  modelId: model.id,
                  size: 17,
                  backgroundColor: Colors.white.withOpacity(0.04),
                  inactiveColor: Colors.white38,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(Icons.chevron_right, color: Colors.white24),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ===================================================================
/// SHARED HELPER - Displays a thumbnail image and uses a graceful
/// fallback icon when the image is missing or cannot be loaded.
/// ===================================================================

Widget networkThumb(String? url, {IconData icon = Icons.view_in_ar}) {
  final clean = url?.trim();

  if (clean == null || clean.isEmpty) {
    return ColoredBox(
      color: const Color(0xFF172027),
      child: Center(
        child: Icon(icon, color: Colors.white24, size: 40),
      ),
    );
  }

  return Image.network(
    clean,
    fit: BoxFit.cover,
    errorBuilder: (context, error, stackTrace) {
      return const ColoredBox(
        color: Color(0xFF172027),
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Colors.white24,
            size: 34,
          ),
        ),
      );
    },
  );
}