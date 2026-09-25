import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:visionar/screens/home/Model%20detail%20screen.dart';
import 'package:visionar/screens/home/model_core.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// ===============================================================
/// MODELS SCREEN
/// ===============================================================
///
/// IMPORTANT LAYOUT FIX
///
/// Earlier the screen used:
///
/// GridView + childAspectRatio
///
/// This forced every card into a fixed height. If the content inside
/// the card was smaller than that height, empty space appeared below
/// the text/stats.
///
/// This version uses:
///
/// LayoutBuilder
///     -> SingleChildScrollView
///         -> Wrap
///             -> Intrinsic-height cards
///
/// Therefore every card finishes immediately after its content.
///
/// CARD:
///
/// ┌─────────────────────────┐
/// │                         │
/// │        IMAGE            │
/// │                         │
/// ├─────────────────────────┤
/// │ ◈ Model Name            │
/// │ 📍 Location             │
/// │ 👁 12     ♥ 0           │
/// └─────────────────────────┘
///
/// No artificial space at bottom.
///
/// ALIGNMENT FIX
///
/// Earlier the whole grid block was wrapped in `Center`, so on wide
/// (desktop) screens with fewer models than the max content width,
/// the entire block of rows appeared centered in the middle of the
/// screen instead of starting from the top-left.
///
/// Now the block is aligned to the top-left (`Alignment.topLeft`)
/// so rows always start from the left edge / first row, exactly
/// like a normal grid, regardless of how many models are present.
/// ===============================================================

class ModelsScreen extends StatefulWidget {
  final String databasePath;

  const ModelsScreen({
    super.key,
    this.databasePath = 'models',
  });

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  late final DatabaseReference modelsRef;

  @override
  void initState() {
    super.initState();

    modelsRef = FirebaseDatabase.instance.ref(
      widget.databasePath,
    );

    debugPrint(
      '[MODELS] Database path: ${modelsRef.path}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F14),
        elevation: 0,
        title: const Text(
          '3D Models',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(
              Icons.refresh,
              color: Colors.white70,
            ),
            onPressed: () {
              setState(() {});
            },
          ),
        ],
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: modelsRef.onValue,
        builder: (
            context,
            snapshot,
            ) {
          if (snapshot.hasError) {
            debugPrint(
              '[MODELS][ERROR] Stream error: ${snapshot.error}',
            );

            return _MessageState(
              icon: Icons.error_outline,
              title: 'Firebase error',
              message: snapshot.error.toString(),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            );
          }

          final event = snapshot.data;

          if (event == null) {
            return const _MessageState(
              icon: Icons.cloud_off,
              title: 'No response from Firebase',
              message:
              'No data was received from the Realtime Database.',
            );
          }

          final children = event.snapshot.children.toList();

          if (children.isEmpty) {
            return const _MessageState(
              icon: Icons.view_in_ar_outlined,
              title: 'No 3D models',
              message:
              'There are no models at the Firebase models path.',
            );
          }

          final models = <ModelRecord>[];

          for (final child in children) {
            try {
              final model = ModelRecord.fromSnapshot(
                child,
              );

              if (model.modelUrl.trim().isNotEmpty) {
                models.add(model);
              }
            } catch (e, stackTrace) {
              debugPrint(
                '[MODELS][ERROR] Parse error for key=${child.key}: $e',
              );

              debugPrint('$stackTrace');
            }
          }

          models.sort(
                (a, b) {
              final aTime =
              a.updatedAt > 0 ? a.updatedAt : a.createdAt;

              final bTime =
              b.updatedAt > 0 ? b.updatedAt : b.createdAt;

              return bTime.compareTo(aTime);
            },
          );

          if (models.isEmpty) {
            return const _MessageState(
              icon: Icons.link_off,
              title: 'No valid model found',
              message:
              'modelUrl is missing from the Firebase records.',
            );
          }

          return LayoutBuilder(
            builder: (
                context,
                constraints,
                ) {
              final width = constraints.maxWidth;

              final deviceType = deviceTypeOf(
                width,
              );

              return _ResponsiveModelsLayout(
                models: models,
                width: width,
                deviceType: deviceType,
              );
            },
          );
        },
      ),
    );
  }
}

/// ===============================================================
/// RESPONSIVE MODELS LAYOUT
/// ===============================================================
///
/// Uses Wrap instead of GridView so cards don't get forced into
/// equal-height rows.
///
/// Each card has its own natural height.
///
/// This completely removes the extra space below the text.
///
/// The block is aligned top-left (not centered) so the first row
/// always starts from the top / left edge of the available area.
/// ===============================================================

class _ResponsiveModelsLayout extends StatelessWidget {
  final List<ModelRecord> models;
  final double width;
  final DeviceType deviceType;

  const _ResponsiveModelsLayout({
    required this.models,
    required this.width,
    required this.deviceType,
  });

  int get columns {
    if (width >= 1600) {
      return 6;
    }

    if (width >= 1200) {
      return 5;
    }

    if (width >= 900) {
      return 4;
    }

    if (width >= 650) {
      return 3;
    }

    return 2;
  }

  double get horizontalPadding {
    switch (deviceType) {
      case DeviceType.mobile:
        return 14;
      case DeviceType.tablet:
        return 22;
      case DeviceType.desktop:
        return 32;
    }
  }

  double get spacing {
    return deviceType.isMobile ? 12 : 16;
  }

  @override
  Widget build(BuildContext context) {
    final maxContentWidth =
    deviceType.isDesktop ? 1800.0 : double.infinity;

    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxContentWidth,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.all(
            horizontalPadding,
          ),
          child: LayoutBuilder(
            builder: (
                context,
                innerConstraints,
                ) {
              final availableWidth =
                  innerConstraints.maxWidth;

              final totalSpacing =
                  spacing * (columns - 1);

              final cardWidth =
                  (availableWidth - totalSpacing) /
                      columns;

              return Wrap(
                alignment: WrapAlignment.start,
                runAlignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.start,
                spacing: spacing,
                runSpacing: spacing,
                children: models.map(
                      (model) {
                    return SizedBox(
                      width: cardWidth,
                      child: _ModelCard(
                        model: model,
                        deviceType: deviceType,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ModelDetailScreen(
                                    model: model,
                                  ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ).toList(),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// ===============================================================
/// MODEL CARD
/// ===============================================================
///
/// NO Expanded
/// NO fixed card height
/// NO childAspectRatio
///
/// Content determines the card height.
/// ===============================================================

class _ModelCard extends StatelessWidget {
  final ModelRecord model;
  final VoidCallback onTap;
  final DeviceType deviceType;

  const _ModelCard({
    required this.model,
    required this.onTap,
    required this.deviceType,
  });

  @override
  Widget build(BuildContext context) {
    final location = model.location?.trim();

    final hasLocation =
        location != null && location.isNotEmpty;

    final titleFontSize =
    deviceType.isMobile ? 14.0 : 15.0;

    final iconSize =
    deviceType.isMobile ? 20.0 : 22.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF151C24),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white12,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              /// =================================================
              /// IMAGE
              /// =================================================
              ///
              /// Fixed aspect ratio only for IMAGE.
              /// The CARD itself has no fixed height.
              /// =================================================

              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  child: _Thumbnail(
                    url: model.thumbnailUrl,
                  ),
                ),
              ),

              /// =================================================
              /// TITLE
              /// =================================================
              ///
              /// Small controlled padding.
              /// No Expanded.
              /// =================================================

              Padding(
                padding: const EdgeInsets.fromLTRB(
                  11,
                  9,
                  11,
                  5,
                ),
                child: Row(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.view_in_ar,
                      color: Colors.white60,
                      size: iconSize,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        model.modelName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              /// =================================================
              /// LOCATION
              /// =================================================
              ///
              /// Only created when location exists.
              /// If location doesn't exist, there is ZERO gap.
              /// =================================================

              if (hasLocation)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    11,
                    0,
                    11,
                    5,
                  ),
                  child: Row(
                    crossAxisAlignment:
                    CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: Color(0xFF8FD5E5),
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          location!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF8FD5E5),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              /// =================================================
              /// STATS
              /// =================================================

              Padding(
                padding: const EdgeInsets.fromLTRB(
                  11,
                  0,
                  11,
                  9,
                ),
                child: _ModelStatsBadgeRow(
                  modelId: model.id,
                  votingEnabled: model.votingEnabled,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ===============================================================
/// MODEL STATS
/// ===============================================================

class _ModelStatsBadgeRow extends StatelessWidget {
  final String modelId;
  final bool votingEnabled;

  const _ModelStatsBadgeRow({
    required this.modelId,
    required this.votingEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: ModelAnalyticsService.statsStream(
        modelId,
      ),
      builder: (
          context,
          snapshot,
          ) {
        int views = 0;
        int likes = 0;

        final data =
            snapshot.data?.snapshot.value;

        if (data is Map) {
          final map =
          Map<dynamic, dynamic>.from(
            data,
          );

          views = asInt(
            map['totalViews'],
          );

          likes = asInt(
            map['likes'],
          );
        }

        if (!votingEnabled) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.remove_red_eye,
                size: 13,
                color: Colors.white38,
              ),
              const SizedBox(width: 3),
              Text(
                '$views',
                style: _badgeStyle,
              ),
              const SizedBox(width: 11),
              const Icon(
                Icons.block,
                size: 12,
                color: Colors.white24,
              ),
              const SizedBox(width: 3),
              const Text(
                'Voting off',
                style: _badgeStyle,
              ),
            ],
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.remove_red_eye,
              size: 13,
              color: Colors.white38,
            ),
            const SizedBox(width: 3),
            Text(
              '$views',
              style: _badgeStyle,
            ),
            const SizedBox(width: 11),
            const Icon(
              Icons.favorite,
              size: 12,
              color: Colors.white38,
            ),
            const SizedBox(width: 3),
            Text(
              '$likes',
              style: _badgeStyle,
            ),
          ],
        );
      },
    );
  }

  static const TextStyle _badgeStyle = TextStyle(
    color: Colors.white54,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.0,
  );
}

/// ===============================================================
/// THUMBNAIL
/// ===============================================================

class _Thumbnail extends StatelessWidget {
  final String? url;

  const _Thumbnail({
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    final clean = url?.trim();

    if (clean == null || clean.isEmpty) {
      return const ColoredBox(
        color: Color(0xFF10151B),
        child: Center(
          child: Icon(
            Icons.view_in_ar,
            color: Colors.white54,
            size: 50,
          ),
        ),
      );
    }

    return Image.network(
      clean,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      loadingBuilder: (
          context,
          child,
          progress,
          ) {
        if (progress == null) {
          return child;
        }

        return const ColoredBox(
          color: Color(0xFF10151B),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white38,
              ),
            ),
          ),
        );
      },
      errorBuilder: (
          context,
          error,
          stackTrace,
          ) {
        debugPrint(
          '[THUMBNAIL][ERROR] '
              'Failed to load $clean: $error',
        );

        return const ColoredBox(
          color: Color(0xFF10151B),
          child: Center(
            child: Image(
              image: AssetImage(
                'assets/vr_icon.png',
              ),
              width: 70,
              height: 70,
              fit: BoxFit.contain,
            ),
          ),
        );
      },
    );
  }
}

/// ===============================================================
/// MESSAGE STATE
/// ===============================================================

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 480,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: Colors.white54,
                size: 52,
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ===============================================================
/// MEDIA VIEWER
/// ===============================================================

class ModelMediaViewerScreen extends StatefulWidget {
  final List<ModelMediaItem> media;
  final int initialIndex;
  final String modelName;

  const ModelMediaViewerScreen({
    super.key,
    required this.media,
    required this.modelName,
    this.initialIndex = 0,
  });

  @override
  State<ModelMediaViewerScreen> createState() =>
      _ModelMediaViewerScreenState();
}

class _ModelMediaViewerScreenState
    extends State<ModelMediaViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();

    if (widget.media.isEmpty) {
      _currentIndex = 0;
    } else {
      _currentIndex =
          widget.initialIndex.clamp(
            0,
            widget.media.length - 1,
          );
    }

    _pageController = PageController(
      initialPage: _currentIndex,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.media.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(
            color: Colors.white,
          ),
        ),
        body: const Center(
          child: Text(
            'No media available',
            style: TextStyle(
              color: Colors.white70,
            ),
          ),
        ),
      );
    }

    final item =
    widget.media[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
        title: Text(
          item.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (widget.media.length > 1)
            Padding(
              padding: const EdgeInsets.only(
                right: 14,
              ),
              child: Center(
                child: Text(
                  '${_currentIndex + 1} / '
                      '${widget.media.length}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (
            context,
            constraints,
            ) {
          final deviceType =
          deviceTypeOf(
            constraints.maxWidth,
          );

          final pageView =
          PageView.builder(
            controller: _pageController,
            itemCount: widget.media.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (
                context,
                index,
                ) {
              final pageItem =
              widget.media[index];

              if (pageItem.isVideo) {
                return _VideoPage(
                  key: ValueKey(
                    'video-${pageItem.id}',
                  ),
                  item: pageItem,
                  isActive:
                  index == _currentIndex,
                );
              }

              return _ImagePage(
                key: ValueKey(
                  'image-${pageItem.id}',
                ),
                item: pageItem,
              );
            },
          );

          Widget body = pageView;

          if (deviceType.isDesktop) {
            body = Center(
              child: ConstrainedBox(
                constraints:
                const BoxConstraints(
                  maxWidth: 1200,
                ),
                child: pageView,
              ),
            );
          }

          if (widget.media.length <= 1) {
            return body;
          }

          return Column(
            children: [
              Expanded(
                child: body,
              ),
              _MediaFilmstrip(
                media: widget.media,
                currentIndex:
                _currentIndex,
                deviceType:
                deviceType,
                onSelect: (index) {
                  _pageController
                      .animateToPage(
                    index,
                    duration:
                    const Duration(
                      milliseconds: 250,
                    ),
                    curve:
                    Curves.easeOut,
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/// ===============================================================
/// MEDIA FILMSTRIP
/// ===============================================================

class _MediaFilmstrip
    extends StatelessWidget {
  final List<ModelMediaItem> media;
  final int currentIndex;
  final DeviceType deviceType;
  final ValueChanged<int> onSelect;

  const _MediaFilmstrip({
    required this.media,
    required this.currentIndex,
    required this.deviceType,
    required this.onSelect,
  });

  double get _chipSize =>
      switch (deviceType) {
        DeviceType.mobile => 56.0,
        DeviceType.tablet => 64.0,
        DeviceType.desktop => 72.0,
      };

  @override
  Widget build(BuildContext context) {
    if (media.length <= 1) {
      return const SizedBox.shrink();
    }

    final chipSize = _chipSize;

    return Container(
      height: chipSize + 20,
      color: Colors.black,
      padding: const EdgeInsets.symmetric(
        vertical: 10,
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics:
        const BouncingScrollPhysics(),
        padding:
        const EdgeInsets.symmetric(
          horizontal: 14,
        ),
        itemCount: media.length,
        separatorBuilder: (
            _,
            __,
            ) =>
        const SizedBox(width: 8),
        itemBuilder: (
            context,
            index,
            ) {
          final item =
          media[index];

          final isActive =
              index == currentIndex;

          return GestureDetector(
            onTap: () => onSelect(index),
            child: Container(
              width: chipSize,
              height: chipSize,
              clipBehavior:
              Clip.antiAlias,
              decoration:
              BoxDecoration(
                color:
                const Color(
                  0xFF0F151B,
                ),
                borderRadius:
                BorderRadius.circular(
                  8,
                ),
                border:
                Border.all(
                  color: isActive
                      ? const Color(
                    0xFF2F86FF,
                  )
                      : Colors.white12,
                  width:
                  isActive ? 2 : 1,
                ),
              ),
              child: item.isImage
                  ? Image.network(
                item.url,
                fit: BoxFit.cover,
                errorBuilder: (
                    context,
                    error,
                    stackTrace,
                    ) {
                  return const Center(
                    child: Icon(
                      Icons
                          .broken_image_outlined,
                      color:
                      Colors.white38,
                      size: 18,
                    ),
                  );
                },
              )
                  : const ColoredBox(
                color:
                Color(
                  0xFF161F29,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// ===============================================================
/// IMAGE VIEWER PAGE
/// ===============================================================

class _ImagePage
    extends StatelessWidget {
  final ModelMediaItem item;

  const _ImagePage({
    super.key,
    required this.item,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      child: Center(
        child: Image.network(
          item.url,
          fit: BoxFit.contain,
          loadingBuilder: (
              context,
              child,
              progress,
              ) {
            if (progress == null) {
              return child;
            }

            return const CircularProgressIndicator(
              color: Colors.white,
            );
          },
          errorBuilder: (
              context,
              error,
              stackTrace,
              ) {
            debugPrint(
              '[MEDIA VIEWER][ERROR] '
                  'Image failed: $error',
            );

            return const Column(
              mainAxisSize:
              MainAxisSize.min,
              children: [
                Icon(
                  Icons
                      .broken_image_outlined,
                  color:
                  Colors.white54,
                  size: 56,
                ),
                SizedBox(
                  height: 10,
                ),
                Text(
                  'Photo failed to load',
                  style:
                  TextStyle(
                    color:
                    Colors.white54,
                    fontSize: 13,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// ===============================================================
/// VIDEO VIEWER PAGE
/// ===============================================================

class _VideoPage
    extends StatefulWidget {
  final ModelMediaItem item;
  final bool isActive;

  const _VideoPage({
    super.key,
    required this.item,
    required this.isActive,
  });

  @override
  State<_VideoPage> createState() =>
      _VideoPageState();
}

class _VideoPageState
    extends State<_VideoPage> {
  VideoPlayerController? _controller;

  bool _hasError = false;
  bool _showControlsOverlay = true;

  @override
  void initState() {
    super.initState();

    if (widget.isActive) {
      _initController();
    }
  }

  @override
  void didUpdateWidget(
      covariant _VideoPage oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (widget.isActive &&
        _controller == null) {
      _initController();
    } else if (!widget.isActive &&
        _controller != null) {
      _disposeController();
    }
  }

  void _initController() {
    final controller =
    VideoPlayerController.networkUrl(
      Uri.parse(widget.item.url),
    );

    _controller = controller;

    controller.initialize().then((_) {
      if (!mounted) {
        return;
      }

      setState(() {});

      controller
        ..setLooping(true)
        ..play();
    }).catchError(
          (
          Object error,
          StackTrace st,
          ) {
        debugPrint(
          '[MEDIA VIEWER][ERROR] '
              'Video init failed: $error',
        );

        debugPrint(
          '[MEDIA VIEWER][ERROR] '
              'StackTrace:\n$st',
        );

        if (!mounted) {
          return;
        }

        setState(() {
          _hasError = true;
        });
      },
    );
  }

  void _disposeController() {
    _controller?.pause();
    _controller?.dispose();
    _controller = null;
  }

  void _togglePlayPause() {
    final controller =
        _controller;

    if (controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }

      _showControlsOverlay = true;
    });
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(
      BuildContext context,
      ) {
    if (_hasError) {
      return const Center(
        child: Column(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color:
              Colors.redAccent,
              size: 48,
            ),
            SizedBox(height: 10),
            Text(
              'Video failed to load',
              style: TextStyle(
                color:
                Colors.white70,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    final controller =
        _controller;

    if (controller == null ||
        !controller.value.isInitialized) {
      return const Center(
        child:
        CircularProgressIndicator(
          color: Colors.white,
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _showControlsOverlay =
          !_showControlsOverlay;
        });
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio:
              controller.value
                  .aspectRatio ==
                  0
                  ? 16 / 9
                  : controller
                  .value
                  .aspectRatio,
              child:
              VideoPlayer(
                controller,
              ),
            ),
          ),

          if (_showControlsOverlay)
            GestureDetector(
              onTap:
              _togglePlayPause,
              child: Container(
                width: 68,
                height: 68,
                decoration:
                BoxDecoration(
                  color: Colors.black
                      .withOpacity(
                    0.45,
                  ),
                  shape:
                  BoxShape.circle,
                ),
                child: Icon(
                  controller
                      .value
                      .isPlaying
                      ? Icons.pause
                      : Icons.play_arrow,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),

          if (_showControlsOverlay)
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child:
              VideoProgressIndicator(
                controller,
                allowScrubbing:
                true,
                padding:
                EdgeInsets.zero,
                colors:
                const VideoProgressColors(
                  playedColor:
                  Color(
                    0xFF2F86FF,
                  ),
                  bufferedColor:
                  Colors.white24,
                  backgroundColor:
                  Colors.white12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// ===============================================================
/// QR SHARE SCREEN
/// ===============================================================

class ModelQrShareScreen
    extends StatelessWidget {
  final ModelRecord model;

  const ModelQrShareScreen({
    super.key,
    required this.model,
  });

  static const String
  _hostedViewerBase =
      'https://rara-a10ab.web.app/viewer.html';

  String get viewerUrl {
    final uri =
    Uri.parse(
      _hostedViewerBase,
    ).replace(
      queryParameters: {
        'model':
        model.modelUrl.trim(),
        'name':
        model.modelName,
        'id':
        model.id,
      },
    );

    return uri.toString();
  }

  String qrImageUrl(int size) {
    final encodedViewerUrl =
    Uri.encodeComponent(
      viewerUrl,
    );

    return 'https://api.qrserver.com/v1/create-qr-code/'
        '?size=${size}x$size'
        '&data=$encodedViewerUrl';
  }

  void _copyLink(
      BuildContext context,
      ) {
    Clipboard.setData(
      ClipboardData(
        text: viewerUrl,
      ),
    );

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      const SnackBar(
        content:
        Text('Link copied'),
      ),
    );
  }

  /// Opens the hosted viewer link.
  ///
  /// FIX (web crash): `webview_flutter` has no web implementation
  /// registered in this project, so pushing `ModelLinkViewerScreen`
  /// (which builds a `WebViewController`) on the web target used to
  /// throw `UnimplementedError: setJavaScriptMode is not implemented
  /// on the current platform` the instant the screen opened - the
  /// model itself was never even reached. On web we now open the
  /// link directly in a NEW BROWSER TAB via `url_launcher` instead
  /// of pushing the WebView-based screen. Native (Android/iOS/
  /// desktop) keeps using the in-app `ModelLinkViewerScreen` exactly
  /// as before.
  Future<void> _openInAppViewer(
      BuildContext context,
      ) async {
    if (kIsWeb) {
      final uri = Uri.parse(viewerUrl);

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );

      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the link.'),
          ),
        );
      }
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ModelLinkViewerScreen(
              url: viewerUrl,
              modelName:
              model.modelName,
            ),
      ),
    );
  }

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      backgroundColor:
      const Color(0xFF070B10),
      appBar: AppBar(
        backgroundColor:
        const Color(0xFF070B10),
        elevation: 0,
        iconTheme:
        const IconThemeData(
          color: Colors.white,
        ),
        title: const Text(
          'Share QR Code',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight:
            FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (
              context,
              constraints,
              ) {
            final deviceType =
            deviceTypeOf(
              constraints.maxWidth,
            );

            final qrBoxSize =
            switch (deviceType) {
              DeviceType.mobile =>
              260.0,
              DeviceType.tablet =>
              300.0,
              DeviceType.desktop =>
              340.0,
            };

            final cardMaxWidth =
            switch (deviceType) {
              DeviceType.mobile =>
              double.infinity,
              DeviceType.tablet =>
              520.0,
              DeviceType.desktop =>
              560.0,
            };

            return SingleChildScrollView(
              padding:
              const EdgeInsets.all(
                20,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints:
                  BoxConstraints(
                    maxWidth:
                    cardMaxWidth,
                  ),
                  child: Column(
                    children: [
                      Text(
                        model.modelName,
                        textAlign:
                        TextAlign.center,
                        style:
                        const TextStyle(
                          color:
                          Colors.white,
                          fontSize: 18,
                          fontWeight:
                          FontWeight.w700,
                        ),
                      ),
                      const SizedBox(
                        height: 6,
                      ),
                      const Text(
                        'Scan this QR code or open the link to view\n'
                            'the model in any browser.',
                        textAlign:
                        TextAlign.center,
                        style:
                        TextStyle(
                          color:
                          Colors.white54,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(
                        height: 24,
                      ),

                      Container(
                        padding:
                        const EdgeInsets
                            .all(18),
                        decoration:
                        BoxDecoration(
                          color:
                          Colors.white,
                          borderRadius:
                          BorderRadius
                              .circular(
                            16,
                          ),
                        ),
                        child:
                        Image.network(
                          qrImageUrl(
                            qrBoxSize
                                .toInt(),
                          ),
                          width:
                          qrBoxSize,
                          height:
                          qrBoxSize,
                          fit: BoxFit
                              .contain,
                          loadingBuilder: (
                              context,
                              child,
                              progress,
                              ) {
                            if (progress ==
                                null) {
                              return child;
                            }

                            return SizedBox(
                              width:
                              qrBoxSize,
                              height:
                              qrBoxSize,
                              child:
                              const Center(
                                child:
                                CircularProgressIndicator(
                                  color: Colors
                                      .black45,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (
                              context,
                              error,
                              stackTrace,
                              ) {
                            return SizedBox(
                              width:
                              qrBoxSize,
                              height:
                              qrBoxSize,
                              child:
                              const Center(
                                child:
                                Icon(
                                  Icons
                                      .qr_code_2,
                                  color: Colors
                                      .black26,
                                  size: 64,
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(
                        height: 24,
                      ),

                      Material(
                        color:
                        const Color(
                          0xFF151C24,
                        ),
                        borderRadius:
                        BorderRadius
                            .circular(
                          10,
                        ),
                        child:
                        InkWell(
                          borderRadius:
                          BorderRadius
                              .circular(
                            10,
                          ),
                          onTap: () =>
                              _openInAppViewer(
                                context,
                              ),
                          child:
                          Padding(
                            padding:
                            const EdgeInsets
                                .symmetric(
                              horizontal:
                              14,
                              vertical: 14,
                            ),
                            child:
                            Row(
                              children: [
                                const Icon(
                                  Icons.link,
                                  color:
                                  Colors.white70,
                                  size: 18,
                                ),
                                const SizedBox(
                                  width: 10,
                                ),
                                Expanded(
                                  child:
                                  Text(
                                    viewerUrl,
                                    maxLines:
                                    2,
                                    overflow:
                                    TextOverflow
                                        .ellipsis,
                                    style:
                                    const TextStyle(
                                      color:
                                      Color(
                                        0xFF6FB4FF,
                                      ),
                                      fontSize:
                                      13,
                                      decoration:
                                      TextDecoration
                                          .underline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(
                        height: 14,
                      ),

                      Row(
                        children: [
                          Expanded(
                            child:
                            OutlinedButton
                                .icon(
                              onPressed:
                                  () =>
                                  _copyLink(
                                    context,
                                  ),
                              style:
                              OutlinedButton
                                  .styleFrom(
                                foregroundColor:
                                Colors.white,
                                side:
                                const BorderSide(
                                  color:
                                  Colors.white24,
                                ),
                                padding:
                                const EdgeInsets
                                    .symmetric(
                                  vertical:
                                  12,
                                ),
                              ),
                              icon:
                              const Icon(
                                Icons.copy,
                                size: 17,
                              ),
                              label:
                              const Text(
                                'Copy Link',
                              ),
                            ),
                          ),
                          const SizedBox(
                            width: 10,
                          ),
                          Expanded(
                            child:
                            FilledButton
                                .icon(
                              onPressed:
                                  () =>
                                  _openInAppViewer(
                                    context,
                                  ),
                              style:
                              FilledButton
                                  .styleFrom(
                                backgroundColor:
                                const Color(
                                  0xFF2F86FF,
                                ),
                                padding:
                                const EdgeInsets
                                    .symmetric(
                                  vertical:
                                  12,
                                ),
                              ),
                              icon:
                              const Icon(
                                Icons
                                    .open_in_new,
                                size: 17,
                              ),
                              label:
                              const Text(
                                'Open Model',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// ===============================================================
/// IN-APP MODEL LINK VIEWER
/// ===============================================================
///
/// This screen is only meant to be reached on NATIVE platforms
/// (Android/iOS/desktop) - `ModelQrShareScreen._openInAppViewer`
/// already routes web straight to an external browser tab instead
/// of pushing this screen. The `kIsWeb` guard below is a second,
/// defensive layer: even if something else ever navigates here on
/// web, it will show a plain "open externally" fallback instead of
/// building a `WebViewController` (which has no web implementation
/// registered in this project and throws
/// `UnimplementedError: setJavaScriptMode is not implemented on the
/// current platform` the instant it's constructed there).
/// ===============================================================

class ModelLinkViewerScreen
    extends StatefulWidget {
  final String url;
  final String modelName;

  const ModelLinkViewerScreen({
    super.key,
    required this.url,
    required this.modelName,
  });

  @override
  State<ModelLinkViewerScreen>
  createState() =>
      _ModelLinkViewerScreenState();
}

class _ModelLinkViewerScreenState
    extends State<
        ModelLinkViewerScreen> {
  /// Nullable now (was `late final`): stays null on web, where
  /// `WebViewController` is never constructed - see the class-level
  /// doc comment above.
  WebViewController?
  _webViewController;

  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();

    if (kIsWeb) {
      // Defensive guard - see class doc comment. Nothing to
      // initialize here; `build` renders the web fallback below.
      _isLoading = false;
      return;
    }

    _webViewController =
    WebViewController()
      ..setJavaScriptMode(
        JavaScriptMode.unrestricted,
      )
      ..setBackgroundColor(
        const Color(
          0xFF0B0F14,
        ),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(
                    () =>
                _isLoading =
                true,
              );
            }
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(
                    () =>
                _isLoading =
                false,
              );
            }
          },
          onWebResourceError:
              (error) {
            debugPrint(
              '[LINK VIEWER][ERROR] '
                  '${error.description}',
            );

            if (mounted) {
              setState(() {
                _hasError =
                true;
                _isLoading =
                false;
              });
            }
          },
        ),
      )
      ..loadRequest(
        Uri.parse(
          widget.url,
        ),
      );
  }

  Future<void> _openExternally() async {
    final uri = Uri.parse(widget.url);

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the link.'),
        ),
      );
    }
  }

  @override
  Widget build(
      BuildContext context,
      ) {
    return Scaffold(
      backgroundColor:
      const Color(0xFF070B10),
      appBar: AppBar(
        backgroundColor:
        const Color(0xFF070B10),
        elevation: 0,
        iconTheme:
        const IconThemeData(
          color: Colors.white,
        ),
        title: Text(
          widget.modelName,
          maxLines: 1,
          overflow:
          TextOverflow.ellipsis,
          style:
          const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight:
            FontWeight.w600,
          ),
        ),
      ),
      body: kIsWeb
          ? _WebOpenLinkFallback(
        url: widget.url,
        onOpen: _openExternally,
      )
          : LayoutBuilder(
        builder: (
            context,
            constraints,
            ) {
          final deviceType =
          deviceTypeOf(
            constraints.maxWidth,
          );

          final stageMaxWidth =
          deviceType.isDesktop
              ? 1400.0
              : double.infinity;

          return Stack(
            children: [
              if (!_hasError)
                Center(
                  child: ConstrainedBox(
                    constraints:
                    BoxConstraints(
                      maxWidth:
                      stageMaxWidth,
                    ),
                    child:
                    WebViewWidget(
                      controller:
                      _webViewController!,
                    ),
                  ),
                )
              else
                const Center(
                  child: Padding(
                    padding:
                    EdgeInsets.all(
                      24,
                    ),
                    child: Column(
                      mainAxisSize:
                      MainAxisSize.min,
                      children: [
                        Icon(
                          Icons
                              .error_outline,
                          color:
                          Colors.redAccent,
                          size: 48,
                        ),
                        SizedBox(
                          height: 10,
                        ),
                        Text(
                          'Link failed to load',
                          style:
                          TextStyle(
                            color: Colors
                                .white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (_isLoading &&
                  !_hasError)
                const Center(
                  child:
                  CircularProgressIndicator(
                    color:
                    Colors.white,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Plain "open this link externally" fallback shown by
/// `ModelLinkViewerScreen` on web (see its class-level doc comment).
/// In normal use the user never actually sees this widget, because
/// `ModelQrShareScreen._openInAppViewer` already opens a new browser
/// tab directly on web instead of pushing `ModelLinkViewerScreen` at
/// all - this only renders if something else navigates here anyway.
class _WebOpenLinkFallback extends StatelessWidget {
  final String url;
  final VoidCallback onOpen;

  const _WebOpenLinkFallback({
    required this.url,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.open_in_new,
                color: Colors.white54,
                size: 48,
              ),
              const SizedBox(height: 14),
              const Text(
                'Open this model in a new tab',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                url,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}