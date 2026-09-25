import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:visionar/screens/home/model_core.dart';

import 'package:visionar/screens/home/models_screen.dart';
import 'package:visionar/screens/home/Model%20detail%20screen.dart';
import 'package:visionar/services/saved_models_service.dart';

/// ===================================================================
/// DISCOVER SCREEN (RESPONSIVE + BACK BUTTON)
/// ===================================================================
/// Same Firebase data source / logic as before. This version adds:
///   - An AppBar with a back arrow (so users can navigate back to
///     Home instead of being stuck on this screen).
///   - Full responsive layout: mobile / tablet / desktop breakpoints,
///     same as Home screen's DeviceType pattern.
///   - Desktop: "Top Projects" grid shows 4 cards per row.
///   - Tablet: 3 cards per row.
///   - Mobile: 2 cards per row (unchanged from before).
/// ===================================================================

void _log(String message) {
  if (kDebugMode) {
    debugPrint('[Discover] $message');
  }
}

/// ---- Responsive breakpoints (mirrors Home screen's DeviceType) ----
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

class DiscoverModel {
  final String id;
  final String modelName;
  final String modelUrl;
  final String thumbnailUrl;
  final String description;
  final String location;
  final String category;
  final String subCategory;
  final String groupIcon;
  final String groupIconUrl;
  final String groupName;
  final bool votingEnabled;
  final int updatedAt;

  final ModelRecord? record;

  DiscoverModel({
    required this.id,
    required this.modelName,
    required this.modelUrl,
    required this.thumbnailUrl,
    required this.description,
    required this.location,
    required this.category,
    required this.subCategory,
    required this.groupIcon,
    required this.groupIconUrl,
    required this.groupName,
    required this.votingEnabled,
    required this.updatedAt,
    required this.record,
  });

  factory DiscoverModel.fromSnapshot(DataSnapshot snapshot) {
    final id = snapshot.key ?? '';
    final rawValue = snapshot.value;
    final map = rawValue is Map ? rawValue : const {};

    String s(dynamic v) => (v ?? '').toString();

    ModelRecord? modelRecord;
    try {
      modelRecord = ModelRecord.fromSnapshot(snapshot);
    } catch (e) {
      _log('WARNING: ModelRecord.fromSnapshot failed for id=$id: $e');
      modelRecord = null;
    }

    final model = DiscoverModel(
      id: id,
      modelName: s(map['modelName']).trim().isEmpty
          ? '3D Model'
          : s(map['modelName']),
      modelUrl: s(map['modelUrl']),
      thumbnailUrl: s(map['thumbnailUrl']),
      description: s(map['description']),
      location: s(map['location']),
      category: s(map['category']).isEmpty ? 'Optional' : s(map['category']),
      subCategory: _resolveSubCategory(s(map['subCategory'])),
      groupIcon: s(map['groupIcon']),
      groupIconUrl: s(map['groupIconUrl']),
      groupName: s(map['groupName']),
      votingEnabled: map['votingEnabled'] == false ? false : true,
      updatedAt: int.tryParse(
          s(map['updatedAt'] ?? map['createdAt']).split('.').first) ??
          0,
      record: modelRecord,
    );

    _log(
      'PARSED MODEL id=$id | name="${model.modelName}" | '
          'category="${model.category}" | subCategory="${model.subCategory}" | '
          'groupName="${model.groupName}" | groupIcon="${model.groupIcon}" | '
          'groupIconUrl=${model.groupIconUrl.isEmpty ? "(none)" : "set"} | '
          'location="${model.location}" | thumbnailUrl='
          '${model.thumbnailUrl.isEmpty ? "(none)" : "set"} | '
          'record=${model.record == null ? "FAILED TO PARSE" : "ok"}',
    );

    return model;
  }

  static const List<String> _validSubCategories = [
    'All',
    'Residential',
    'Commercial',
    'Plot',
    'Villa',
  ];

  static String _resolveSubCategory(String value) {
    return _validSubCategories.contains(value) ? value : 'All';
  }

  bool get hasGroup => groupName.trim().isNotEmpty;

  String get effectiveGroupIcon {
    final url = groupIconUrl.trim();
    if (url.isNotEmpty) return url;

    final icon = groupIcon.trim();
    return icon;
  }

  bool get groupIconIsImage {
    final icon = effectiveGroupIcon;
    return icon.isNotEmpty && icon.startsWith('http');
  }
}

class _DiscoverFilter {
  final String label;
  final String value;
  const _DiscoverFilter(this.label, this.value);
}

const List<_DiscoverFilter> kDiscoverFilters = [
  _DiscoverFilter('All', 'All'),
  _DiscoverFilter('Residential', 'Residential'),
  _DiscoverFilter('Commercial', 'Commercial'),
  _DiscoverFilter('Plots', 'Plot'),
  _DiscoverFilter('Villas', 'Villa'),
];

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  static const Color kBg = Color(0xFF0A0F14);
  static const Color kSearchBar = Color(0xFF111820);
  static const Color kChipBg = Color(0xFF111820);
  static const Color kChipActive = Color(0xFFE8B93D);
  static const Color kCard = Color(0xFF111820);
  static const Color kGold = Color(0xFFE8B93D);
  static const Color kMuted = Color(0xFF8B97A3);
  static const Color kGroupChipBg = Color(0xFF18212B);

  final DatabaseReference _modelsRef =
  FirebaseDatabase.instance.ref('models');

  final TextEditingController _searchController = TextEditingController();

  List<DiscoverModel> _allModels = [];
  bool _isLoading = true;
  String? _errorMessage;

  String _searchQuery = '';
  String _selectedSubCategory = 'All';
  String? _selectedGroupName;

  @override
  void initState() {
    super.initState();
    _log('initState -> attaching listener to path "models"');
    SavedModelsService.instance.init();
    _listenToModels();
    _searchController.addListener(() {
      setState(
              () => _searchQuery = _searchController.text.trim().toLowerCase());
      _log('SEARCH QUERY CHANGED -> "$_searchQuery"');
      _logComputedCounts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _listenToModels() {
    _modelsRef.onValue.listen((event) {
      try {
        _log('RAW SNAPSHOT EXISTS = ${event.snapshot.exists}');
        _log('RAW SNAPSHOT VALUE  = ${jsonEncode(event.snapshot.value)}');
      } catch (e) {
        _log(
            'RAW SNAPSHOT VALUE (could not JSON-encode): ${event.snapshot.value}');
      }

      final items = <DiscoverModel>[];
      int totalInDb = 0;

      if (event.snapshot.exists) {
        totalInDb = event.snapshot.children.length;

        for (final child in event.snapshot.children) {
          if (child.value is Map) {
            final model = DiscoverModel.fromSnapshot(child);
            if (model.category == 'Discover') {
              items.add(model);
            }
          } else {
            _log(
                'SKIPPED key=${child.key} because its value is not a Map: ${child.value}');
          }
        }
      } else {
        _log('RAW SNAPSHOT IS EMPTY -> "models" path is empty or missing.');
      }

      items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      _log('TOTAL IN DB = $totalInDb');
      _log('DISCOVER CATEGORY COUNT = ${items.length}');

      if (!mounted) return;
      setState(() {
        _allModels = items;
        _isLoading = false;
        _errorMessage = null;
      });

      _logComputedCounts();
    }, onError: (error) {
      _log('LISTENER ERROR: $error');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    });
  }

  void _logComputedCounts() {
    _log(
      'CURRENT FILTERS -> subCategory="$_selectedSubCategory", '
          'group="${_selectedGroupName ?? "(none)"}", search="$_searchQuery"',
    );
    _log('AFTER SEARCH+FILTER COUNT = ${_filteredModels.length}');
    _log('GROUP TILES COUNT = ${_groupTiles.length}');
    _log('FINAL LIST (ON SCREEN) COUNT = ${_finalModels.length}');

    for (final m in _finalModels) {
      _log(
        '  -> WILL RENDER CARD: "${m.modelName}" (id=${m.id}) | '
            'group="${m.groupName}" | '
            'groupIcon=${m.groupIconIsImage ? "image:" + m.effectiveGroupIcon : m.effectiveGroupIcon} | '
            'record=${m.record == null ? "FAILED TO PARSE" : "ok"}',
      );
    }
  }

  List<DiscoverModel> get _filteredModels {
    return _allModels.where((model) {
      final matchesSearch = _searchQuery.isEmpty ||
          model.modelName.toLowerCase().contains(_searchQuery) ||
          model.location.toLowerCase().contains(_searchQuery) ||
          model.groupName.toLowerCase().contains(_searchQuery);

      final matchesSubCategory = _selectedSubCategory == 'All' ||
          model.subCategory == _selectedSubCategory;

      return matchesSearch && matchesSubCategory;
    }).toList();
  }

  List<DiscoverModel> get _groupTiles {
    final seen = <String>{};
    final tiles = <DiscoverModel>[];

    for (final model in _filteredModels) {
      if (!model.hasGroup) continue;
      final key = model.groupName.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      tiles.add(model);
    }

    return tiles;
  }

  List<DiscoverModel> get _finalModels {
    if (_selectedGroupName == null) return _filteredModels;

    return _filteredModels
        .where((m) =>
    m.groupName.toLowerCase() == _selectedGroupName!.toLowerCase())
        .toList();
  }

  void _openModelDetail(DiscoverModel model) {
    _log('PROJECT CARD TAPPED -> "${model.modelName}" (id=${model.id})');

    final record = model.record;
    if (record == null) {
      _log('  -> cannot open detail screen, record failed to parse.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this project.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ModelDetailScreen(model: record),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _log(
      'BUILD -> isLoading=$_isLoading, error=$_errorMessage, '
          'allModels=${_allModels.length}',
    );

    return Scaffold(
      backgroundColor: kBg,
      // ---- Back arrow so the user can return to Home -----------------
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Back',
        ),
        title: const Text(
          'Discover Projects',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final deviceType = _deviceTypeOf(constraints.maxWidth);

            final horizontalPadding = switch (deviceType) {
              _DeviceType.mobile => 18.0,
              _DeviceType.tablet => 32.0,
              _DeviceType.desktop => 48.0,
            };

            if (_isLoading) {
              return const Center(
                  child: CircularProgressIndicator(color: kGold));
            }
            if (_errorMessage != null) {
              return _buildError();
            }

            return RefreshIndicator(
              color: kGold,
              backgroundColor: kCard,
              onRefresh: () async {
                _log('MANUAL PULL-TO-REFRESH triggered');
                await Future.delayed(const Duration(milliseconds: 400));
              },
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                    horizontalPadding, 12, horizontalPadding, 24),
                children: [
                  _buildSearchBar(deviceType),
                  const SizedBox(height: 14),
                  _buildFilterChips(deviceType),
                  const SizedBox(height: 26),
                  if (_groupTiles.isNotEmpty) ...[
                    _buildSectionHeader('Featured Developers', deviceType),
                    const SizedBox(height: 14),
                    _buildGroupRow(deviceType),
                    const SizedBox(height: 26),
                  ] else
                    Builder(builder: (_) {
                      _log(
                        'NOTE: "Featured Developers" section hidden '
                            'because no filtered model has a non-empty '
                            'groupName.',
                      );
                      return const SizedBox.shrink();
                    }),
                  _buildSectionHeader('Top Projects', deviceType),
                  const SizedBox(height: 14),
                  _buildProjectsList(deviceType),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildError() {
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
              'Could not load projects.\n$_errorMessage',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(_DeviceType deviceType) {
    final height = switch (deviceType) {
      _DeviceType.mobile => 50.0,
      _DeviceType.tablet => 54.0,
      _DeviceType.desktop => 56.0,
    };
    final fontSize = deviceType.isMobile ? 13.5 : 14.5;

    return Container(
      height: height,
      constraints: const BoxConstraints(maxWidth: 640),
      decoration: BoxDecoration(
        color: kSearchBar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: Colors.white, fontSize: fontSize),
        decoration: InputDecoration(
          icon: const Padding(
            padding: EdgeInsets.only(left: 14),
            child: Icon(Icons.search_rounded, color: Colors.white38, size: 20),
          ),
          hintText: 'Search locations, projects, developers...',
          hintStyle: TextStyle(color: Colors.white38, fontSize: fontSize),
          border: InputBorder.none,
          contentPadding:
          const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        ),
      ),
    );
  }

  Widget _buildFilterChips(_DeviceType deviceType) {
    final height = deviceType.isMobile ? 38.0 : 42.0;
    final fontSize = deviceType.isMobile ? 12.5 : 13.5;
    final hPad = deviceType.isMobile ? 18.0 : 22.0;

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kDiscoverFilters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = kDiscoverFilters[index];
          final isSelected = _selectedSubCategory == filter.value;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedSubCategory = filter.value;
                _selectedGroupName = null;
              });
              _log(
                  'FILTER CHIP TAPPED -> "${filter.label}" (value=${filter.value})');
              _logComputedCounts();
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: hPad),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? kChipActive : kChipBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color:
                  isSelected ? kChipActive : Colors.white.withOpacity(0.08),
                ),
              ),
              child: Text(
                filter.label,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF0A0F14) : Colors.white70,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, _DeviceType deviceType) {
    final fontSize = switch (deviceType) {
      _DeviceType.mobile => 16.0,
      _DeviceType.tablet => 18.0,
      _DeviceType.desktop => 20.0,
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Text(
          'View All',
          style: TextStyle(
            color: kGold,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildGroupIconContent(DiscoverModel model, {required double size}) {
    final icon = model.effectiveGroupIcon;

    if (icon.isEmpty) {
      return Icon(Icons.apartment_rounded,
          color: const Color(0xFF0A0F14), size: size * 0.38);
    }

    if (model.groupIconIsImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.2),
        child: Image.network(
          icon,
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (_, __, ___) {
            _log(
              'GROUP ICON IMAGE FAILED TO LOAD for '
                  '"${model.groupName}": $icon',
            );
            return Icon(Icons.apartment_rounded,
                color: const Color(0xFF0A0F14), size: size * 0.38);
          },
        ),
      );
    }

    return Text(icon, style: TextStyle(fontSize: size * 0.38));
  }

  Widget _buildGroupRow(_DeviceType deviceType) {
    final tiles = _groupTiles;

    final tileSize = switch (deviceType) {
      _DeviceType.mobile => 68.0,
      _DeviceType.tablet => 84.0,
      _DeviceType.desktop => 96.0,
    };
    final rowHeight = tileSize + 32;
    final labelWidth = tileSize + 10;

    return SizedBox(
      height: rowHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final model = tiles[index];
          final isSelected = _selectedGroupName?.toLowerCase() ==
              model.groupName.toLowerCase();

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedGroupName = isSelected ? null : model.groupName;
              });
              _log('GROUP TILE TAPPED -> "${model.groupName}"');
              _logComputedCounts();
            },
            child: Column(
              children: [
                Container(
                  width: tileSize,
                  height: tileSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? kGold : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: _buildGroupIconContent(model, size: tileSize),
                ),
                const SizedBox(height: 7),
                SizedBox(
                  width: labelWidth,
                  child: Text(
                    model.groupName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isSelected ? kGold : Colors.white70,
                      fontSize: deviceType.isMobile ? 11.5 : 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProjectGroupChip(DiscoverModel model) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: kGroupChipBg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(child: _buildGroupIconContent(model, size: 24)),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            model.groupName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// ---- Top Projects grid ------------------------------------------
  /// Mobile: 2 per row. Tablet: 3 per row. Desktop: 4 per row.
  Widget _buildProjectsList(_DeviceType deviceType) {
    final models = _finalModels;

    if (models.isEmpty) {
      _log('TOP PROJECTS LIST IS EMPTY -> showing empty-state message.');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: const [
            Icon(Icons.search_off_rounded, color: Colors.white24, size: 36),
            SizedBox(height: 10),
            Text(
              'No projects match your search/filter.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final crossAxisCount = switch (deviceType) {
      _DeviceType.mobile => 2,
      _DeviceType.tablet => 3,
      _DeviceType.desktop => 4,
    };

    final aspectRatio = switch (deviceType) {
      _DeviceType.mobile => 0.72,
      _DeviceType.tablet => 0.78,
      _DeviceType.desktop => 0.8,
    };

    final spacing = deviceType.isMobile ? 14.0 : 18.0;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: models.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: aspectRatio,
      ),
      itemBuilder: (context, index) =>
          _buildProjectCard(models[index], deviceType),
    );
  }

  Widget _buildProjectCard(DiscoverModel model, _DeviceType deviceType) {
    final nameFontSize = switch (deviceType) {
      _DeviceType.mobile => 13.0,
      _DeviceType.tablet => 14.0,
      _DeviceType.desktop => 15.0,
    };
    final locationFontSize = deviceType.isMobile ? 11.5 : 12.5;
    final saveIconSize = deviceType.isMobile ? 15.0 : 17.0;

    return GestureDetector(
      onTap: () => _openModelDetail(model),
      child: Container(
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  model.thumbnailUrl.trim().isEmpty
                      ? Container(
                    color: Colors.white.withOpacity(0.04),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.apartment_rounded,
                      color: Colors.white24,
                      size: 32,
                    ),
                  )
                      : Image.network(
                    model.thumbnailUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (context, error, stackTrace) {
                      _log(
                        'THUMBNAIL FAILED TO LOAD for "${model.modelName}": '
                            '${model.thumbnailUrl} | error=$error',
                      );
                      return Container(
                        color: Colors.white.withOpacity(0.04),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white24,
                          size: 28,
                        ),
                      );
                    },
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: SaveButton(modelId: model.id, size: saveIconSize),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.modelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: nameFontSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (model.location.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      model.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: kMuted,
                        fontSize: locationFontSize,
                      ),
                    ),
                  ],
                  if (model.hasGroup) _buildProjectGroupChip(model),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}