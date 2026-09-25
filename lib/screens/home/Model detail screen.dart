import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:visionar/screens/home/model_core.dart';
import 'package:visionar/screens/home/models_list_screen.dart';
import 'package:visionar/screens/home/models_screen.dart';


/// ===================================================================
/// MODEL DETAIL SCREEN (RESPONSIVE)
/// ===================================================================
/// Same behaviour as before (hero image carousel, title, location,
/// description, media gallery, "Open 3D Model" button) but now scales
/// cleanly across mobile / tablet / desktop:
///
/// - Hero image area gets taller on larger screens and is NOT cropped
///   on desktop anymore (BoxFit.fitWidth instead of BoxFit.cover).
/// - Text content and the "Open 3D Model" button are centered inside
///   a wider max-width column on desktop.
/// - Media gallery tiles get bigger on tablet/desktop.
///
/// Back navigation: SliverAppBar already shows the default back arrow
/// automatically whenever this screen is pushed with Navigator.push.
/// ===================================================================

enum _DeviceType { mobile, tablet, desktop }

_DeviceType _deviceTypeOf(double width) {
  if (width >= 1100) return _DeviceType.desktop;
  if (width >= 650) return _DeviceType.tablet;
  return _DeviceType.mobile;
}

extension _DeviceTypeX on _DeviceType {
  bool get isMobile => this == _DeviceType.mobile;
  bool get isTablet => this == _DeviceType.tablet;
  bool get isDesktop => this == _DeviceType.desktop;
}

class ModelDetailScreen extends StatefulWidget {
  final ModelRecord model;

  const ModelDetailScreen({
    super.key,
    required this.model,
  });

  @override
  State<ModelDetailScreen> createState() => _ModelDetailScreenState();
}

class _ModelDetailScreenState extends State<ModelDetailScreen> {
  ModelRecord get model => widget.model;

  bool get _hasMedia => model.media.isNotEmpty;

  String? get _location {
    final value = model.location?.trim();
    return (value != null && value.isNotEmpty) ? value : null;
  }

  String? get _externalImageUrl {
    final value = model.externalImageUrl?.trim();
    return (value != null && value.isNotEmpty) ? value : null;
  }

  String? get _thumbnailUrl {
    final value = model.thumbnailUrl?.trim();
    return (value != null && value.isNotEmpty) ? value : null;
  }

  List<String> get _heroImages {
    final images = <String>[];

    if (_thumbnailUrl != null) images.add(_thumbnailUrl!);

    if (_externalImageUrl != null && _externalImageUrl != _thumbnailUrl) {
      images.add(_externalImageUrl!);
    }

    return images;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final deviceType = _deviceTypeOf(constraints.maxWidth);

            // Fix 1: taller hero on desktop so the banner isn't
            // squeezed / cropped like on mobile.
            final heroHeight = switch (deviceType) {
              _DeviceType.mobile => 260.0,
              _DeviceType.tablet => 360.0,
              _DeviceType.desktop =>
              MediaQuery.of(context).size.height * 0.65,
            };

            final horizontalPadding = switch (deviceType) {
              _DeviceType.mobile => 18.0,
              _DeviceType.tablet => 40.0,
              _DeviceType.desktop => 64.0,
            };

            // Fix 2: wider content column on desktop.
            final maxContentWidth = switch (deviceType) {
              _DeviceType.mobile => double.infinity,
              _DeviceType.tablet => 760.0,
              _DeviceType.desktop => 1400.0,
            };

            return Column(
              children: [
                Expanded(
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      _buildAppBarSliver(context, heroHeight),
                      SliverToBoxAdapter(
                        child: Center(
                          child: ConstrainedBox(
                            constraints:
                            BoxConstraints(maxWidth: maxContentWidth),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(horizontalPadding,
                                  18, horizontalPadding, 14),
                              child: Column(
                                // Fix 3: center content on desktop instead
                                // of hugging the left edge.
                                crossAxisAlignment: deviceType.isDesktop
                                    ? CrossAxisAlignment.center
                                    : CrossAxisAlignment.start,
                                children: [
                                  _buildTitleRow(deviceType),
                                  if (_location != null) ...[
                                    const SizedBox(height: 8),
                                    _buildLocationRow(
                                        _location!, deviceType),
                                  ],
                                  const SizedBox(height: 14),
                                  Align(
                                    alignment: deviceType.isDesktop
                                        ? Alignment.center
                                        : Alignment.centerLeft,
                                    child: SizedBox(
                                      width: deviceType.isDesktop
                                          ? 1000
                                          : double.infinity,
                                      child: _buildDescription(deviceType),
                                    ),
                                  ),
                                  if (_hasMedia) ...[
                                    const SizedBox(height: 22),
                                    _buildSectionHeader(
                                      icon: Icons.photo_library_outlined,
                                      title: 'Photos & Videos',
                                      trailing: '${model.media.length}',
                                      deviceType: deviceType,
                                    ),
                                    const SizedBox(height: 12),
                                    _MediaGallery(
                                      media: model.media,
                                      modelName: model.modelName,
                                      deviceType: deviceType,
                                    ),
                                  ],
                                  const SizedBox(height: 100),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildOpenButtonBar(context, deviceType, maxContentWidth),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAppBarSliver(BuildContext context, double heroHeight) {
    return SliverAppBar(
      backgroundColor: const Color(0xFF0B0F14),
      pinned: true,
      stretch: true,
      expandedHeight: heroHeight,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [
          StretchMode.zoomBackground,
          StretchMode.fadeTitle,
        ],
        background: Hero(
          tag: 'model-thumb-${model.id}',
          child: _HeroImageCarousel(images: _heroImages),
        ),
      ),
    );
  }

  Widget _buildTitleRow(_DeviceType deviceType) {
    final fontSize = switch (deviceType) {
      _DeviceType.mobile => 21.0,
      _DeviceType.tablet => 24.0,
      _DeviceType.desktop => 27.0,
    };
    final iconSize = deviceType.isMobile ? 24.0 : 28.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.view_in_ar, color: const Color(0xFF2F86FF), size: iconSize),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            model.modelName,
            textAlign:
            deviceType.isDesktop ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationRow(String location, _DeviceType deviceType) {
    final fontSize = deviceType.isMobile ? 13.0 : 14.5;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 1),
          child: Icon(
            Icons.location_on_outlined,
            color: Color(0xFF8FD5E5),
            size: 16,
          ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            location,
            textAlign:
            deviceType.isDesktop ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              color: const Color(0xFF8FD5E5),
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDescription(_DeviceType deviceType) {
    final text = (model.description?.trim().isNotEmpty ?? false)
        ? model.description!.trim()
        : 'No description available.';
    final fontSize = deviceType.isMobile ? 13.5 : 15.0;

    return Text(
      text,
      textAlign: deviceType.isDesktop ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        color: Colors.white70,
        fontSize: fontSize,
        height: 1.5,
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required _DeviceType deviceType,
    String? trailing,
  }) {
    final fontSize = deviceType.isMobile ? 15.0 : 17.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white54, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              trailing,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOpenButtonBar(
      BuildContext context, _DeviceType deviceType, double maxContentWidth) {
    final horizontalPadding = switch (deviceType) {
      _DeviceType.mobile => 18.0,
      _DeviceType.tablet => 40.0,
      _DeviceType.desktop => 64.0,
    };

    return Container(
      padding:
      EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0B0F14),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Center(
        child: ConstrainedBox(
          // Fix 5: wider button on desktop.
          constraints: BoxConstraints(
            maxWidth: deviceType.isDesktop ? 700.0 : maxContentWidth,
          ),
          child: SizedBox(
            width: double.infinity,
            height: deviceType.isMobile ? 52 : 58,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2F86FF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ModelFullViewScreen(model: model),
                  ),
                );
              },
              icon: Icon(Icons.view_in_ar,
                  size: deviceType.isMobile ? 22 : 24),
              label: Text(
                'Open 3D Model',
                style: TextStyle(
                  fontSize: deviceType.isMobile ? 15 : 16.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ===================================================================
/// HERO IMAGE CAROUSEL (thumbnail + optional External Image)
/// ===================================================================
class _HeroImageCarousel extends StatefulWidget {
  final List<String> images;

  const _HeroImageCarousel({required this.images});

  @override
  State<_HeroImageCarousel> createState() => _HeroImageCarouselState();
}

class _HeroImageCarouselState extends State<_HeroImageCarousel> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _hasMultipleImages => widget.images.length > 1;

  void _goToPage(int index) {
    final count = widget.images.length;
    if (count == 0) return;

    final target = (index + count) % count;

    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _goToPrevious() => _goToPage(_currentIndex - 1);

  void _goToNext() => _goToPage(_currentIndex + 1);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.images.isEmpty)
          const _DetailThumbnail(url: null)
        else
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            itemBuilder: (context, index) {
              return _DetailThumbnail(url: widget.images[index]);
            },
          ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x99000000),
                  Colors.transparent,
                  Color(0xCC0B0F14),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),
        if (_hasMultipleImages) ...[
          Positioned(
            left: 6,
            top: 0,
            bottom: 0,
            child: Center(
              child: _CarouselArrowButton(
                icon: Icons.chevron_left,
                onTap: _goToPrevious,
              ),
            ),
          ),
          Positioned(
            right: 6,
            top: 0,
            bottom: 0,
            child: Center(
              child: _CarouselArrowButton(
                icon: Icons.chevron_right,
                onTap: _goToNext,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.images.length, (index) {
                final isActive = index == _currentIndex;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 3.5),
                  width: isActive ? 20 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white
                        : Colors.white.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 3,
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ],
    );
  }
}

class _CarouselArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CarouselArrowButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.38),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, color: Colors.white, size: 24),
        ),
      ),
    );
  }
}

/// ===================================================================
/// HERO THUMBNAIL / BANNER IMAGE
/// ===================================================================
/// KEY FIX: on desktop we no longer use BoxFit.cover (which crops /
/// zooms the image) or BoxFit.fitWidth (which still clips the bottom
/// of tall images inside a fixed-height box). Instead we use
/// BoxFit.contain so the ENTIRE image is always visible, top and
/// bottom, with no cropping at all — any leftover space is simply
/// filled with the background color (letterboxed). Mobile and tablet
/// keep BoxFit.cover so the hero still looks like a filled banner on
/// small screens.
/// ===================================================================
class _DetailThumbnail extends StatelessWidget {
  final String? url;

  const _DetailThumbnail({required this.url});

  @override
  Widget build(BuildContext context) {
    final clean = url?.trim();

    if (clean == null || clean.isEmpty) {
      return const ColoredBox(
        color: Color(0xFF10151B),
        child: Center(
          child: Icon(
            Icons.view_in_ar,
            color: Colors.white38,
            size: 70,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1100;

        return ColoredBox(
          color: const Color(0xFF10151B),
          child: Image.network(
            clean,
            width: double.infinity,
            height: double.infinity,
            fit: isDesktop ? BoxFit.contain : BoxFit.cover,
            alignment: Alignment.center,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const ColoredBox(
                color: Color(0xFF10151B),
                child: Center(
                  child: CircularProgressIndicator(
                    color: Colors.white38,
                    strokeWidth: 2,
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return const ColoredBox(
                color: Color(0xFF10151B),
                child: Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white38,
                    size: 60,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// ===================================================================
/// MEDIA GALLERY STRIP (Photos & Videos section on the detail screen)
/// ===================================================================
class _MediaGallery extends StatelessWidget {
  final List<ModelMediaItem> media;
  final String modelName;
  final _DeviceType deviceType;

  const _MediaGallery({
    required this.media,
    required this.modelName,
    required this.deviceType,
  });

  double get _tileSize => switch (deviceType) {
    _DeviceType.mobile => 96.0,
    _DeviceType.tablet => 112.0,
    _DeviceType.desktop => 130.0,
  };

  @override
  Widget build(BuildContext context) {
    final tileSize = _tileSize;

    return SizedBox(
      height: tileSize,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: media.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = media[index];

          return GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ModelMediaViewerScreen(
                    media: media,
                    initialIndex: index,
                    modelName: modelName,
                  ),
                ),
              );
            },
            child: Container(
              width: tileSize,
              height: tileSize,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFF121A21),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.isImage)
                    Image.network(
                      item.url,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white38,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white38,
                            size: 22,
                          ),
                        );
                      },
                    )
                  else
                    const ColoredBox(color: Color(0xFF161F29)),
                  if (item.isVideo)
                    Container(
                      color: Colors.black.withOpacity(0.28),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.play_circle_fill,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  Positioned(
                    left: 4,
                    right: 4,
                    bottom: 4,
                    child: Text(
                      item.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 3),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

