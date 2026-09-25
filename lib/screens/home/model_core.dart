import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;

const int kMaxGlbBytes = 250 * 1024 * 1024;

/// ===================================================================
/// RESPONSIVE HELPERS
/// ===================================================================
/// Shared across every screen in this app so mobile / tablet / web /
/// desktop all get a layout tuned to their width, using the same
/// breakpoints everywhere (mirrors the pattern used on the detail
/// screen). `deviceTypeOf` only looks at width, so it works the same
/// whether the app is running on a phone, a resized browser window on
/// the web, or a desktop window.
///
/// These are PUBLIC (no leading underscore) because they are used
/// from every file in this app (model_core.dart, models_list_screen.dart,
/// model_full_view_screen.dart). Dart's `_` privacy is per-library-file,
/// so anything shared across files must not be prefixed with `_`.
/// ===================================================================

enum DeviceType { mobile, tablet, desktop }

DeviceType deviceTypeOf(double width) {
  if (width >= 1100) return DeviceType.desktop;
  if (width >= 650) return DeviceType.tablet;
  return DeviceType.mobile;
}

extension DeviceTypeX on DeviceType {
  bool get isMobile => this == DeviceType.mobile;
  bool get isTablet => this == DeviceType.tablet;
  bool get isDesktop => this == DeviceType.desktop;
}

/// Whether it's safe to touch native, mobile-only platform APIs
/// (orientation lock, immersive system UI, etc). Flutter Web has no
/// `dart:io.Platform`, so `kIsWeb` is always checked FIRST.
bool get isMobilePlatform {
  if (kIsWeb) return false;
  try {
    return Platform.isAndroid || Platform.isIOS;
  } catch (_) {
    return false;
  }
}

/// Safe int parsing from Realtime Database values, which can come
/// back as int, double, or String depending on how they were written.
int asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool asBool(dynamic value, {required bool fallback}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;

  final text = value.toString().trim().toLowerCase();
  if (text.isEmpty) return fallback;
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;

  return fallback;
}

class ModelMediaItem {
  final String id;
  final String type; // 'image' | 'video'
  final String url;
  final String name;
  final String storagePath;
  final int addedAt;

  const ModelMediaItem({
    required this.id,
    required this.type,
    required this.url,
    required this.name,
    required this.storagePath,
    required this.addedAt,
  });

  bool get isVideo => type == 'video';

  bool get isImage => !isVideo;

  /// Display label shown under the chip / in the viewer app bar -
  /// falls back to a generic label when no file name was stored.
  String get displayName {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return isVideo ? 'Video' : 'Photo';
  }

  factory ModelMediaItem.fromEntry(String id, dynamic rawValue) {
    final Map<dynamic, dynamic> data = rawValue is Map
        ? Map<dynamic, dynamic>.from(rawValue)
        : <dynamic, dynamic>{};

    final typeText = data['type']?.toString().trim().toLowerCase() ?? '';

    return ModelMediaItem(
      id: id,
      type: typeText == 'video' ? 'video' : 'image',
      url: data['url']?.toString().trim() ?? '',
      name: data['name']?.toString().trim() ?? '',
      storagePath: data['storagePath']?.toString().trim() ?? '',
      addedAt: asInt(data['addedAt']),
    );
  }
}

List<ModelMediaItem> _parseModelMedia(dynamic rawMedia) {
  if (rawMedia is! Map) return const <ModelMediaItem>[];

  final items = <ModelMediaItem>[];

  rawMedia.forEach((key, value) {
    final item = ModelMediaItem.fromEntry(
      key.toString(),
      value,
    );

    if (item.url.isNotEmpty) {
      items.add(item);
    }
  });

  items.sort((a, b) => b.addedAt.compareTo(a.addedAt));

  return items;
}

/// ===============================================================
/// MODEL RECORD
/// ===============================================================

class ModelRecord {
  final String id;
  final String modelName;
  final String modelUrl;
  final String? thumbnailUrl;
  final String? description;

  /// Free-text place/address (or "lat,lng") describing where this
  /// model/object is associated with. Fully optional - written by
  /// the admin panel's "Location" field, and read here the exact
  /// same way `description` is (nullable, trimmed, empty -> null).
  /// Models uploaded before this feature existed simply have `null`
  /// here, which is fully backward compatible.
  final String? location;

  /// A second, independent reference image for this model - fully
  /// optional and separate from [thumbnailUrl]. Written by the admin
  /// panel's "External Image URL" / "External Image Upload" fields
  /// (Firebase field: `externalImageUrl`), and read here the exact
  /// same way [location] is (nullable, trimmed, empty -> null).
  /// Models uploaded before this feature existed simply have `null`
  /// here, which is fully backward compatible. Used by the detail
  /// screen to show an image carousel (thumbnail + external image)
  /// when both are set.
  final String? externalImageUrl;

  final String? fileName;
  final String? storagePath;
  final int createdAt;
  final int updatedAt;

  /// `true` - see [ModelRecord.fromSnapshot].
  final bool votingEnabled;

  /// The `category` field written by the admin panel when a model is
  /// uploaded/updated (Recommended / Govt / My Project / Discover /
  /// Optional) - the Home screen uses this field to decide which
  /// section each model shows up in. It should always hold one of
  /// the known valid values (see [categoryOptions]) - if the field
  /// is missing in Firebase or holds an unknown value,
  /// [_resolveCategory] falls back to 'Optional', which matches the
  /// default behavior for older models that were uploaded before
  /// this feature existed.
  final String category;

  final List<ModelMediaItem> media;

  const ModelRecord({
    required this.id,
    required this.modelName,
    required this.modelUrl,
    required this.thumbnailUrl,
    required this.description,
    required this.location,
    required this.externalImageUrl,
    required this.fileName,
    required this.storagePath,
    required this.createdAt,
    required this.updatedAt,
    required this.votingEnabled,
    required this.category,
    required this.media,
  });

  factory ModelRecord.fromSnapshot(
      DataSnapshot snapshot,
      ) {
    final raw = snapshot.value;

    final Map<dynamic, dynamic> data =
    raw is Map ? Map<dynamic, dynamic>.from(raw) : <dynamic, dynamic>{};

    return ModelRecord(
      id: snapshot.key ?? '',
      modelName: _string(
        data['modelName'],
        fallback: '3D Model',
      ),
      modelUrl: _string(data['modelUrl']),
      thumbnailUrl: _nullable(data['thumbnailUrl']),
      description: _nullable(data['description']),
      location: _nullable(data['location']),
      externalImageUrl: _nullable(data['externalImageUrl']),
      fileName: _nullable(data['fileName']),
      storagePath: _nullable(data['storagePath']),
      createdAt: _int(data['createdAt']),
      updatedAt: _int(data['updatedAt']),
      // FIX 10: default to `true` when the field is absent, so
      // models uploaded before this feature existed keep behaving
      // exactly like they always did (voting available).
      votingEnabled: asBool(data['votingEnabled'], fallback: true),
      // Category: parse + validate against the known admin-panel
      // options, falling back to 'Optional' for missing/unknown
      // values (old records, typos, manual DB edits, etc).
      category: _resolveCategory(data['category']),
      // FIX 11: parse the photos/videos gallery map.
      media: _parseModelMedia(data['media']),
    );
  }

  /// Known category values written by the admin panel. Kept here
  /// (rather than only in the admin panel code) so this list is the
  /// single source of truth for what counts as a "valid" category on
  /// the read side too - e.g. useful for building a filter dropdown
  /// in-app without duplicating the string list elsewhere.
  static const List<String> categoryOptions = <String>[
    'Recommended',
    'Govt',
    'My Project',
    'Discover',
    'Optional',
  ];

  static String _resolveCategory(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return categoryOptions.contains(text) ? text : 'Optional';
  }

  static String _string(
      dynamic value, {
        String fallback = '',
      }) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String? _nullable(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();

    return int.tryParse(
      value?.toString() ?? '',
    ) ??
        0;
  }
}

class LocalHttpModelServer {
  HttpServer? _server;

  Uint8ListHolder? _modelBytes;

  int? _port;

  String? _modelDisplayName;

  int? get port => _port;

  bool get isRunning => _server != null && _port != null;

  /// URL for the raw GLB, used by Flutter3DViewer inside the app.
  String? get modelUrl {
    if (_port == null) return null;
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _port!,
      path: '/model.glb',
    ).toString();
  }

  /// URL for the in-app stereo VR page.
  String? get vrViewerUrl {
    if (_port == null) return null;
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _port!,
      path: '/viewer.html',
    ).toString();
  }

  Future<String> serveGlb(
      List<int> bytes, {
        String fileName = 'model.glb',
        String modelDisplayName = '3D Model',
      }) async {
    await stop();

    if (bytes.isEmpty) {
      debugPrint('[LOCAL SERVER][ERROR] Received empty GLB bytes.');
      throw StateError(
        'Local HTTP server received empty GLB bytes.',
      );
    }

    final copy = Uint8ListHolder(
      bytes.toList(growable: false),
    );

    _modelBytes = copy;
    _modelDisplayName = modelDisplayName;

    try {
      /// Bind only to loopback.
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
        shared: false,
      );
    } catch (e, st) {
      debugPrint('[LOCAL SERVER][ERROR] Failed to bind local server: $e');
      debugPrint('[LOCAL SERVER][ERROR] StackTrace:\n$st');
      rethrow;
    }

    _port = _server!.port;

    debugPrint(
      '[LOCAL SERVER] Started on '
          '127.0.0.1:$_port',
    );
    debugPrint(
      '[LOCAL SERVER] Model URL will be: $modelUrl',
    );
    debugPrint(
      '[LOCAL SERVER] IMPORTANT (Android): this is a PLAIN HTTP url. '
          'If the app manifest does not allow cleartext traffic to '
          '127.0.0.1/localhost, the WebView used by flutter_3d_controller '
          'will silently refuse to load it. See network_security_config.xml.',
    );

    unawaited(
      _listenForRequests(_server!),
    );

    return modelUrl!;
  }

  Future<void> _listenForRequests(
      HttpServer server,
      ) async {
    try {
      await for (final request in server) {
        unawaited(_handleRequest(request));
      }
    } catch (e, st) {
      debugPrint(
        '[LOCAL SERVER][ERROR] Listener stopped: $e',
      );
      debugPrint('[LOCAL SERVER][ERROR] StackTrace:\n$st');
    }
  }

  Future<void> _handleRequest(
      HttpRequest request,
      ) async {
    final response = request.response;

    response.headers.set(
      HttpHeaders.accessControlAllowOriginHeader,
      '*',
    );
    response.headers.set(
      HttpHeaders.accessControlAllowMethodsHeader,
      'GET, HEAD, OPTIONS',
    );
    response.headers.set(
      HttpHeaders.accessControlAllowHeadersHeader,
      '*',
    );

    try {
      if (request.method == 'OPTIONS') {
        response.statusCode = HttpStatus.noContent;
        await response.close();
        return;
      }

      final path = request.uri.path;

      debugPrint('[LOCAL SERVER] ${request.method} $path');

      if (path == '/model.glb') {
        await _serveModel(request, response);
        return;
      }

      if (path == '/viewer.html') {
        await _serveViewerHtml(request, response);
        return;
      }

      response.statusCode = HttpStatus.notFound;
      await response.close();
    } catch (e, st) {
      debugPrint('[LOCAL SERVER][ERROR] _handleRequest failed: $e');
      debugPrint('[LOCAL SERVER][ERROR] StackTrace:\n$st');
      try {
        response.statusCode = HttpStatus.internalServerError;
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveModel(
      HttpRequest request,
      HttpResponse response,
      ) async {
    response.headers.contentType = ContentType(
      'model',
      'gltf-binary',
      charset: null,
    );

    response.headers.set(
      HttpHeaders.cacheControlHeader,
      'no-store, no-cache, must-revalidate',
    );

    final data = _modelBytes?.bytes;

    if (data == null || data.isEmpty) {
      debugPrint('[LOCAL SERVER][ERROR] /model.glb requested but no bytes in memory.');
      response.statusCode = HttpStatus.serviceUnavailable;
      await response.close();
      return;
    }

    response.headers.contentLength = data.length;

    if (request.method == 'HEAD') {
      response.statusCode = HttpStatus.ok;
      await response.close();
      return;
    }

    if (request.method != 'GET') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }

    response.statusCode = HttpStatus.ok;
    response.add(data);
    await response.close();

    debugPrint(
      '[LOCAL SERVER] Served model: '
          '${data.length} bytes',
    );
  }

  Future<void> _serveViewerHtml(
      HttpRequest request,
      HttpResponse response,
      ) async {
    final html = _buildStereoVrHtml(
      title: _modelDisplayName ?? '3D Model',
    );
    final bytes = utf8.encode(html);

    response.headers.contentType = ContentType(
      'text',
      'html',
      charset: 'utf-8',
    );

    response.headers.set(
      HttpHeaders.cacheControlHeader,
      'no-store, no-cache, must-revalidate',
    );

    if (request.method == 'HEAD') {
      response.headers.contentLength = bytes.length;
      response.statusCode = HttpStatus.ok;
      await response.close();
      return;
    }

    if (request.method != 'GET') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }

    response.headers.contentLength = bytes.length;
    response.statusCode = HttpStatus.ok;
    response.add(bytes);
    await response.close();

    debugPrint(
      '[LOCAL SERVER] Served VR viewer.html',
    );
  }

  String _buildStereoVrHtml({required String title}) {
    final safeTitle = title.replaceAll('<', '').replaceAll('>', '');

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover" />
<title>$safeTitle - VR</title>
<style>
  html, body { margin: 0; padding: 0; height: 100%; background: #000; overflow: hidden; touch-action: none; }
  #app-canvas { position: fixed; top: 0; left: 0; width: 100%; height: 100%; display: block; }
  #divider {
    position: fixed; top: 0; bottom: 0; left: 50%; width: 1px;
    background: rgba(255,255,255,0.12); pointer-events: none; z-index: 4;
  }
  #loading {
    position: fixed; inset: 0; display: flex; align-items: center; justify-content: center;
    color: #fff; font-family: sans-serif; font-size: 14px; z-index: 10; background: #000;
  }
  #hint {
    position: fixed; left: 0; right: 0; top: 8px; text-align: center;
    color: #ffffff77; font-family: sans-serif; font-size: 11px; pointer-events: none; z-index: 5;
  }
  #vr-toolbar {
    position: fixed; left: 0; right: 0; bottom: 10px;
    display: flex; justify-content: center; align-items: center; gap: 8px;
    z-index: 6; pointer-events: none;
  }
  #vr-toolbar button {
    pointer-events: auto;
    width: 36px; height: 36px; border-radius: 50%;
    border: 1px solid rgba(255,255,255,0.25);
    background: rgba(21,28,36,0.85);
    color: #fff; font-size: 15px; line-height: 1;
    display: flex; align-items: center; justify-content: center;
    font-family: sans-serif;
  }
  #vr-toolbar button.active {
    background: #2F86FF;
    border-color: #fff;
  }
  #vr-toolbar button:active {
    background: #3a4553;
  }
</style>
</head>
<body>
  <div id="loading">Loading 3D model&hellip;</div>
  <canvas id="app-canvas"></canvas>
  <div id="divider"></div>
  <div id="hint">Move your head to look around &bull; double-tap to re-center</div>

  <div id="vr-toolbar">
    <button id="btn-up" onclick="vrMoveUp()" title="Move up">&#9650;</button>
    <button id="btn-down" onclick="vrMoveDown()" title="Move down">&#9660;</button>
    <button id="btn-zoomin" onclick="vrZoomIn()" title="Zoom in">+</button>
    <button id="btn-zoomout" onclick="vrZoomOut()" title="Zoom out">&minus;</button>
    <button id="btn-autorotate" onclick="vrToggleAutoRotate()" title="Auto rotate">&#8635;</button>
    <button id="btn-anim" onclick="vrToggleAnimation()" title="Play/Pause animation" style="display:none;">&#9654;</button>
    <button id="btn-reset" onclick="vrReset()" title="Reset position">&#8853;</button>
  </div>

  <script type="importmap">
  {
    "imports": {
      "three": "https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.js",
      "three/addons/": "https://cdn.jsdelivr.net/npm/three@0.160.0/examples/jsm/"
    }
  }
  </script>

  <script type="module">
    import * as THREE from 'three';
    import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

    const canvas = document.getElementById('app-canvas');
    const loadingEl = document.getElementById('loading');

    // ---- Renderer / scene -------------------------------------------------
    const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x000000);

    const hemiLight = new THREE.HemisphereLight(0xffffff, 0x223344, 1.15);
    scene.add(hemiLight);
    const dirLight = new THREE.DirectionalLight(0xffffff, 1.3);
    dirLight.position.set(3, 5, 2);
    scene.add(dirLight);

    // ---- Stereo rig: one head object, two eye cameras ---------------------
    const EYE_SEPARATION = 0.064; // meters, average human IPD
    const rig = new THREE.Object3D();
    rig.position.set(0, 1.4, 0);
    scene.add(rig);

    const leftCamera = new THREE.PerspectiveCamera(70, 1, 0.01, 1000);
    leftCamera.position.set(-EYE_SEPARATION / 2, 0, 0);
    rig.add(leftCamera);

    const rightCamera = new THREE.PerspectiveCamera(70, 1, 0.01, 1000);
    rightCamera.position.set(EYE_SEPARATION / 2, 0, 0);
    rig.add(rightCamera);

    // ---- Load model ---------------------------------------------------
    let modelRoot = null;
    const clock = new THREE.Clock();

    // Animation playback (FIX 4 - parity with normal 3D view).
    let mixer = null;
    let animationAction = null;
    let isAnimationPlaying = false;

    // Move Up/Down + Zoom In/Out + Auto Rotate state (FIX 4 / FIX 5).
    // The model always sits at (0, baseModelY + verticalOffset, -distance)
    // in front of the rig; distance shrinks/grows with zoomOffset but the
    // position stays fixed between button presses (no drift), and Auto
    // Rotate spins modelRoot.rotation.y regardless of the current zoom.
    let baseModelY = 1.4;
    let baseModelDistance = 2.2;
    let verticalOffset = 0;
    let zoomOffset = 0;
    let autoRotateEnabled = false;

    const VERTICAL_STEP = 0.3;
    const ZOOM_STEP = 0.3;
    const MIN_ZOOM_DISTANCE = 0.6;
    const MAX_ZOOM_DISTANCE = 6.0;
    const AUTO_ROTATE_SPEED = 0.006; // radians per frame

    function applyModelTransform() {
      if (!modelRoot) return;
      // FIX 6: keep x pinned to 0 explicitly. Centering the model
      // (position.sub(center)) only zeroes x/y/z once at load time;
      // without re-asserting x here, an asymmetric bounding box could
      // leave the model visibly offset to one side.
      modelRoot.position.x = 0;
      modelRoot.position.y = baseModelY + verticalOffset;
      const distance = Math.min(
        MAX_ZOOM_DISTANCE,
        Math.max(MIN_ZOOM_DISTANCE, baseModelDistance - zoomOffset)
      );
      modelRoot.position.z = -distance;
    }

    function updateAutoRotateButton() {
      const btn = document.getElementById('btn-autorotate');
      if (btn) btn.classList.toggle('active', autoRotateEnabled);
    }

    function updateAnimationButton() {
      const btn = document.getElementById('btn-anim');
      if (!btn) return;
      btn.textContent = isAnimationPlaying ? '\\u23F8' : '\\u25B6';
    }

    // Exposed globally so the plain <button onclick="..."> handlers in
    // the toolbar (outside this module's scope) can reach them.
    window.vrMoveUp = function () {
      verticalOffset += VERTICAL_STEP;
      applyModelTransform();
    };
    window.vrMoveDown = function () {
      verticalOffset -= VERTICAL_STEP;
      applyModelTransform();
    };
    window.vrZoomIn = function () {
      zoomOffset += ZOOM_STEP;
      applyModelTransform();
    };
    window.vrZoomOut = function () {
      zoomOffset -= ZOOM_STEP;
      applyModelTransform();
    };
    window.vrToggleAutoRotate = function () {
      autoRotateEnabled = !autoRotateEnabled;
      updateAutoRotateButton();
    };
    window.vrToggleAnimation = function () {
      if (!mixer || !animationAction) return;
      isAnimationPlaying = !isAnimationPlaying;
      animationAction.paused = !isAnimationPlaying;
      updateAnimationButton();
    };
    window.vrReset = function () {
      verticalOffset = 0;
      zoomOffset = 0;
      autoRotateEnabled = false;
      applyModelTransform();
      updateAutoRotateButton();
      if (modelRoot) modelRoot.rotation.y = 0;
    };

    const loader = new GLTFLoader();
    loader.load(
      '/model.glb',
      (gltf) => {
        modelRoot = gltf.scene;

        // FIX 1: disable frustum culling on every mesh so nothing
        // flickers in/out of view due to a bad/animated bounding
        // sphere while the head-tracked camera rotates. Also render
        // both sides so thin/open meshes never disappear depending
        // on which way the camera is facing.
        modelRoot.traverse((obj) => {
          obj.frustumCulled = false;
          if (obj.isMesh && obj.material) {
            const materials = Array.isArray(obj.material) ? obj.material : [obj.material];
            materials.forEach((mat) => { mat.side = THREE.DoubleSide; });
          }
        });

        const box = new THREE.Box3().setFromObject(modelRoot);
        const size = new THREE.Vector3();
        const center = new THREE.Vector3();
        box.getSize(size);
        box.getCenter(center);

        const maxDim = Math.max(size.x, size.y, size.z) || 1;
        const scale = 1.2 / maxDim;
        modelRoot.scale.setScalar(scale);

        box.setFromObject(modelRoot);
        box.getCenter(center);
        modelRoot.position.sub(center);

        // FIX 5: anchor position/zoom is applied through
        // applyModelTransform() instead of a one-time offset, so
        // Move Up/Down and Zoom In/Out can adjust it afterwards
        // while it stays fixed between button presses.
        applyModelTransform();

        scene.add(modelRoot);
        loadingEl.style.display = 'none';

        // FIX 4: wire up Play/Pause if the model has animation clips.
        if (gltf.animations && gltf.animations.length > 0) {
          mixer = new THREE.AnimationMixer(modelRoot);
          animationAction = mixer.clipAction(gltf.animations[0]);
          animationAction.play();
          isAnimationPlaying = true;

          const animBtn = document.getElementById('btn-anim');
          if (animBtn) {
            animBtn.style.display = 'flex';
          }
          updateAnimationButton();
        }
      },
      undefined,
      (err) => {
        loadingEl.textContent = 'Failed to load model: ' + (err && err.message ? err.message : err);
        console.error('[VR VIEWER] GLTFLoader error:', err);
      }
    );

    // ---- Device-orientation head tracking (auto, no button) --------------
    const DEG2RAD = Math.PI / 180;
    let rawAlpha = 0, beta = 0, gamma = 0;
    let alphaOffset = null;
    let sensorActive = false;
    let lastSensorEventAt = 0;

    // How long without a fresh sensor event before we stop trusting
    // the sensor for THIS frame and fall back to the (synced) manual
    // orientation. Kept fairly generous - the important fix is that
    // the fallback no longer jumps (see FIX 6 below), so this value
    // only affects how quickly touch-drag can "take over".
    const SENSOR_STALE_MS = 2000;

    // FIX 2: the very first deviceorientation sample right after the
    // page/permission is granted is often noisy, which used to lock
    // "forward" in a random direction. Now we wait for several
    // consecutive samples and use their CIRCULAR MEAN (alpha wraps at
    // 0/360) as the calibration offset, instead of trusting whichever
    // single sample happened to arrive last.
    let calibSamples = [];
    const ORIENTATION_STABLE_SAMPLES = 8;

    function currentScreenAngle() {
      if (screen.orientation && typeof screen.orientation.angle === 'number') {
        return screen.orientation.angle;
      }
      return (window.orientation || 0);
    }

    function circularMeanDegrees(samplesDeg) {
      let sumSin = 0;
      let sumCos = 0;
      for (const deg of samplesDeg) {
        const rad = deg * DEG2RAD;
        sumSin += Math.sin(rad);
        sumCos += Math.cos(rad);
      }
      return Math.atan2(sumSin, sumCos) / DEG2RAD;
    }

    function onDeviceOrientation(e) {
      if (e.alpha === null || e.beta === null || e.gamma === null) return;

      rawAlpha = e.alpha;
      beta = e.beta;
      gamma = e.gamma;

      if (alphaOffset === null) {
        calibSamples.push(rawAlpha);
        if (calibSamples.length >= ORIENTATION_STABLE_SAMPLES) {
          alphaOffset = circularMeanDegrees(calibSamples);
          calibSamples = [];
        }
      }

      sensorActive = true;
      lastSensorEventAt = performance.now();
    }
    window.addEventListener('deviceorientation', onDeviceOrientation, true);

    const zAxis = new THREE.Vector3(0, 0, 1);
    const euler = new THREE.Euler();
    const sensorQuaternion = new THREE.Quaternion();
    const screenTransform = new THREE.Quaternion();
    const worldTransform = new THREE.Quaternion(-Math.sqrt(0.5), 0, 0, Math.sqrt(0.5));

    function sensorQuaternionFromOrientation() {
      const alpha = (rawAlpha - (alphaOffset === null ? rawAlpha : alphaOffset)) * DEG2RAD;
      const b = beta * DEG2RAD;
      const g = gamma * DEG2RAD;
      const screenAngle = currentScreenAngle() * DEG2RAD;

      euler.set(b, alpha, -g, 'YXZ');
      sensorQuaternion.setFromEuler(euler);
      sensorQuaternion.multiply(worldTransform);
      sensorQuaternion.multiply(screenTransform.setFromAxisAngle(zAxis, -screenAngle));
      return sensorQuaternion;
    }

    let manualYaw = 0, manualPitch = 0;
    let dragging = false, lastX = 0, lastY = 0;
    let lastTapAt = 0;

    canvas.addEventListener('pointerdown', (e) => {
      dragging = true;
      lastX = e.clientX;
      lastY = e.clientY;

      const now = performance.now();
      if (now - lastTapAt < 300) {
        // double-tap -> re-center forward direction
        alphaOffset = rawAlpha;
        manualYaw = 0;
        manualPitch = 0;
      }
      lastTapAt = now;
    });
    canvas.addEventListener('pointerup', () => { dragging = false; });
    canvas.addEventListener('pointercancel', () => { dragging = false; });
    canvas.addEventListener('pointermove', (e) => {
      if (!dragging) return;
      const dx = e.clientX - lastX;
      const dy = e.clientY - lastY;
      lastX = e.clientX;
      lastY = e.clientY;
      manualYaw -= dx * 0.005;
      manualPitch -= dy * 0.005;
      manualPitch = Math.max(-1.4, Math.min(1.4, manualPitch));
    });

    function applyManualLookToRig() {
      euler.set(manualPitch, manualYaw, 0, 'YXZ');
      rig.quaternion.setFromEuler(euler);
    }

    // ---- Resize / viewport ------------------------------------------------
    function onResize() {
      const w = window.innerWidth;
      const h = window.innerHeight;
      if (w <= 0 || h <= 0) return; // ignore transient 0-size layout passes

      renderer.setSize(w, h, false);

      const eyeAspect = (w / 2) / h;
      leftCamera.aspect = eyeAspect;
      leftCamera.updateProjectionMatrix();
      rightCamera.aspect = eyeAspect;
      rightCamera.updateProjectionMatrix();
    }
    window.addEventListener('resize', onResize);
    window.addEventListener('orientationchange', () => {
      // The immersive-landscape switch on the Flutter side can take a
      // moment to settle; re-check a few times instead of once.
      setTimeout(onResize, 50);
      setTimeout(onResize, 200);
      setTimeout(onResize, 500);
    });
    onResize();

    // ---- Render loop --------------------------------------------------
    renderer.setAnimationLoop(() => {
      const delta = clock.getDelta();
      if (mixer) mixer.update(delta);

      const sensorIsStale = performance.now() - lastSensorEventAt > SENSOR_STALE_MS;
      const useSensor = sensorActive && !sensorIsStale && alphaOffset !== null;

      if (useSensor) {
        const q = sensorQuaternionFromOrientation();
        rig.quaternion.copy(q);

        euler.setFromQuaternion(q, 'YXZ');
        manualYaw = euler.y;
        manualPitch = Math.max(-1.4, Math.min(1.4, euler.x));
      } else {
        applyManualLookToRig();
      }

      if (modelRoot) {
        if (autoRotateEnabled) {
          // FIX 5: Auto Rotate spins the model in place at whatever
          // zoom/vertical position it currently sits at.
          modelRoot.rotation.y += AUTO_ROTATE_SPEED;
        } else if (!useSensor && !dragging) {
          // gentle idle rotation only when there's no head-tracking/drag input
          modelRoot.rotation.y += 0.001;
        }
      }

      const w = window.innerWidth;
      const h = window.innerHeight;
      if (w <= 0 || h <= 0) return; // FIX 6: never render into a 0-size canvas

      renderer.setScissorTest(true);

      renderer.setViewport(0, 0, w / 2, h);
      renderer.setScissor(0, 0, w / 2, h);
      renderer.render(scene, leftCamera);

      renderer.setViewport(w / 2, 0, w / 2, h);
      renderer.setScissor(w / 2, 0, w / 2, h);
      renderer.render(scene, rightCamera);
    });
  </script>
</body>
</html>
''';
  }

  Future<void> stop() async {
    _modelBytes = null;
    _modelDisplayName = null;
    _port = null;

    final server = _server;
    _server = null;

    if (server != null) {
      try {
        await server.close(force: true);
      } catch (e) {
        debugPrint('[LOCAL SERVER][WARN] close() threw: $e');
      }
    }
  }
}

class Uint8ListHolder {
  final List<int> bytes;

  const Uint8ListHolder(this.bytes);
}

class ModelAnalyticsService {
  ModelAnalyticsService._();

  static const String statsPath = 'modelStats';
  static const String viewsPath = 'modelViews';
  static const String votesPath = 'modelVotes';

  /// Sessions shorter than this are treated as accidental taps and
  /// are not logged, so they don't skew "average time spent".
  static const int minLoggableSeconds = 2;

  static DatabaseReference get _root => FirebaseDatabase.instance.ref();

  static User? get currentUser => FirebaseAuth.instance.currentUser;

  static Future<void> logViewSession({
    required String modelId,
    required DateTime startedAt,
    required int durationSeconds,
  }) async {
    if (modelId.isEmpty) return;
    if (durationSeconds < minLoggableSeconds) return;

    final user = currentUser;

    final sessionData = <String, dynamic>{
      'uid': user?.uid ?? 'anonymous',
      'displayName': user?.displayName ?? '',
      'email': user?.email ?? '',
      'durationSeconds': durationSeconds,
      'startedAt': startedAt.millisecondsSinceEpoch,
      'endedAt': DateTime.now().millisecondsSinceEpoch,
    };

    try {
      await _root.child('$viewsPath/$modelId').push().set(sessionData);

      await _root.child('$statsPath/$modelId/totalViews').runTransaction(
            (value) => Transaction.success(_asInt(value) + 1),
      );

      await _root
          .child('$statsPath/$modelId/totalDurationSeconds')
          .runTransaction(
            (value) => Transaction.success(_asInt(value) + durationSeconds),
      );

      debugPrint(
        '[ANALYTICS] Logged ${durationSeconds}s view session for $modelId '
            '(uid: ${user?.uid ?? "anonymous"})',
      );
    } catch (e, st) {
      debugPrint('[ANALYTICS][ERROR] logViewSession failed: $e');
      debugPrint('[ANALYTICS][ERROR] StackTrace:\n$st');
    }
  }

  /// Live stream of `modelStats/{modelId}` - totalViews, likes,
  /// dislikes etc, used to show quick badges without reading the
  /// full session/vote logs.
  static Stream<DatabaseEvent> statsStream(String modelId) {
    return _root.child('$statsPath/$modelId').onValue;
  }

  /// Live stream of the CURRENT user's own vote on a model, so the
  /// like/dislike buttons can highlight the active choice. Emits
  /// nothing if no one is signed in.
  static Stream<DatabaseEvent> myVoteStream(String modelId) {
    final uid = currentUser?.uid;
    if (uid == null) return const Stream<DatabaseEvent>.empty();
    return _root.child('$votesPath/$modelId/$uid').onValue;
  }

  static Future<void> setVote({
    required String modelId,
    required String voteType, // 'like' | 'dislike'
  }) async {
    final user = currentUser;
    if (user == null) {
      debugPrint('[ANALYTICS] setVote skipped: no signed-in user.');
      return;
    }

    final voteRef = _root.child('$votesPath/$modelId/${user.uid}');

    try {
      final snapshot = await voteRef.get();

      final existing = snapshot.value is Map
          ? Map<dynamic, dynamic>.from(snapshot.value as Map)
          : null;

      final existingType = existing?['type']?.toString();

      if (existingType == voteType) {
        // Same vote tapped again -> remove it.
        await voteRef.remove();
        await _adjustVoteCount(modelId, voteType, -1);
        return;
      }

      if (existingType != null) {
        // Switching from like -> dislike (or vice versa): un-count
        // the old vote before counting the new one.
        await _adjustVoteCount(modelId, existingType, -1);
      }

      await voteRef.set(<String, dynamic>{
        'type': voteType,
        'displayName': user.displayName ?? '',
        'email': user.email ?? '',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      await _adjustVoteCount(modelId, voteType, 1);
    } catch (e, st) {
      debugPrint('[ANALYTICS][ERROR] setVote failed: $e');
      debugPrint('[ANALYTICS][ERROR] StackTrace:\n$st');
    }
  }

  static Future<void> _adjustVoteCount(
      String modelId,
      String voteType,
      int delta,
      ) async {
    final field = voteType == 'like' ? 'likes' : 'dislikes';

    await _root.child('$statsPath/$modelId/$field').runTransaction((value) {
      final next = _asInt(value) + delta;
      return Transaction.success(next < 0 ? 0 : next);
    });
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class NativeGlbDownloader {
  NativeGlbDownloader({
    http.Client? client,
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// Downloads the model's GLB bytes with REAL-TIME progress reporting
  /// and detailed debug logging at every failure point.
  ///
  /// FIXED vs the old implementation:
  ///  - `onProgress` used to fire only ONCE, after the entire file had
  ///    already been buffered via `streamed.stream.toBytes()`. That made
  ///    the progress bar look frozen/stuck the whole download, then jump
  ///    straight to 100%. Now it fires on every received chunk.
  ///  - A 60s connection timeout was added so a dead/unreachable host
  ///    doesn't hang the loading screen forever with no feedback.
  ///  - Oversized downloads are now aborted mid-stream instead of only
  ///    being checked after being fully buffered into memory.
  ///  - Every failure path now has an explicit `debugPrint` with the
  ///    real underlying exception + stack trace.
  ///  - FIX 13 (CORS on web): on the web, `Cache-Control` / `Pragma`
  ///    request headers are NOT "CORS-safelisted" headers. Sending them
  ///    forces the browser to run a CORS preflight (OPTIONS) request,
  ///    and that preflight only succeeds if the Storage bucket's CORS
  ///    config explicitly lists those exact header names in its
  ///    `responseHeader` list. Since most `cors.json` setups (including
  ///    the one in this project's setup notes) don't list them, the
  ///    preflight gets rejected with:
  ///      "Request header field cache-control is not allowed by
  ///       Access-Control-Allow-Headers in preflight response."
  ///    even though `gsutil cors set` was run correctly. The fix is to
  ///    simply not send those two headers on web - they were only ever
  ///    a "don't use a stale cached copy" hint, which isn't needed here
  ///    since every download already carries a fresh, single-use token
  ///    in the URL. Native (Android/iOS/desktop) platforms aren't
  ///    subject to browser CORS at all, so they keep sending both
  ///    headers exactly as before.
  Future<List<int>> download({
    required ModelRecord model,
    void Function(
        int received,
        int total,
        )?
    onProgress,
  }) async {
    final url = model.modelUrl.trim();

    if (url.isEmpty) {
      debugPrint(
        '[3D DOWNLOAD][ERROR] modelUrl is empty for model id=${model.id} '
            'name=${model.modelName}',
      );
      throw StateError(
        'Firebase modelUrl is empty.',
      );
    }

    final uri = Uri.tryParse(url);

    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      debugPrint('[3D DOWNLOAD][ERROR] Invalid Firebase modelUrl: $url');
      throw StateError(
        'Invalid Firebase modelUrl:\n$url',
      );
    }

    if (uri.scheme != 'https' && uri.scheme != 'http') {
      debugPrint('[3D DOWNLOAD][ERROR] Unsupported URL scheme: ${uri.scheme}');
      throw StateError(
        'Unsupported URL scheme: ${uri.scheme}',
      );
    }

    debugPrint('========================================');
    debugPrint('[3D DOWNLOAD] Starting');
    debugPrint('[3D DOWNLOAD] URL: $url');
    debugPrint('[3D DOWNLOAD] Model: ${model.modelName}');
    debugPrint('========================================');

    final request = http.Request('GET', uri);

    // FIX 13: `Accept` is a CORS-safelisted request header, so it never
    // triggers a preflight. `Cache-Control` / `Pragma` are NOT
    // safelisted - only add them on non-web platforms, where there is
    // no browser CORS preflight to fail.
    request.headers.addAll(
      <String, String>{
        'Accept': 'model/gltf-binary, application/octet-stream, */*',
        if (!kIsWeb) 'Cache-Control': 'no-cache',
        if (!kIsWeb) 'Pragma': 'no-cache',
      },
    );

    http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          debugPrint(
            '[3D DOWNLOAD][ERROR] Connection to $url timed out after 60s.',
          );
          throw TimeoutException(
            'Connecting to the model server timed out. Check your '
                'internet connection and try again.',
          );
        },
      );
    } catch (e, st) {
      // On the web, a cross-origin GLB fetch that the browser blocks
      // (missing/incorrect CORS headers on the Storage bucket, or a
      // preflight rejected because of a non-safelisted request header)
      // surfaces here as a generic "ClientException: Failed to fetch"
      // with no HTTP status at all - the request never even reaches
      // the response stage. Re-throw with an explanation instead of
      // the raw browser message so it's actionable from the UI.
      debugPrint('[3D DOWNLOAD][ERROR] Request send failed: $e');
      debugPrint('[3D DOWNLOAD][ERROR] StackTrace:\n$st');

      if (kIsWeb) {
        throw StateError(
          'Could not download the 3D model in the browser.\n\n'
              'This is almost always a CORS problem on the Firebase '
              'Storage bucket for this web origin. Two things to check:\n'
              '1) Run:\n'
              '   gsutil cors set cors.json gs://<your-bucket>\n'
              '   with this site\'s origin listed under "origin".\n'
              '2) Make sure cors.json\'s "responseHeader" list does NOT '
              'need to include Cache-Control/Pragma - this app no longer '
              'sends those headers on web, so a plain GET/HEAD + Accept '
              'is all that\'s required.\n\n'
              'Original error: $e',
        );
      }
      rethrow;
    }

    debugPrint('[3D DOWNLOAD] HTTP ${streamed.statusCode}');

    if (streamed.statusCode != HttpStatus.ok) {
      final errorBody = await streamed.stream.bytesToString();

      final shortBody =
      errorBody.length > 1000 ? errorBody.substring(0, 1000) : errorBody;

      debugPrint(
        '[3D DOWNLOAD][ERROR] Non-200 response: ${streamed.statusCode}',
      );
      debugPrint('[3D DOWNLOAD][ERROR] Body: $shortBody');

      throw HttpException(
        'GLB download failed.\n'
            'HTTP: ${streamed.statusCode}\n'
            'Response: $shortBody',
      );
    }

    final total = streamed.contentLength ?? -1;

    debugPrint('[3D DOWNLOAD] Content-Length: $total bytes');

    if (total > kMaxGlbBytes) {
      debugPrint(
        '[3D DOWNLOAD][ERROR] Declared size ${total}B exceeds max '
            '${kMaxGlbBytes}B',
      );
      throw StateError(
        'GLB is ${(total / 1024 / 1024).toStringAsFixed(1)} MB. '
            'Maximum '
            '${(kMaxGlbBytes / 1024 / 1024).toStringAsFixed(0)} MB is allowed.',
      );
    }

    // ---- STREAMING DOWNLOAD WITH REAL-TIME PROGRESS ----------------------
    // This is the core fix: instead of buffering the ENTIRE response with
    // `await streamed.stream.toBytes()` and only THEN calling onProgress
    // once, we listen chunk-by-chunk and call onProgress every time new
    // bytes arrive. This is what actually drives a moving progress bar.
    final bytes = <int>[];
    int received = 0;

    final completer = Completer<void>();
    late StreamSubscription<List<int>> subscription;

    subscription = streamed.stream.listen(
          (chunk) {
        bytes.addAll(chunk);
        received += chunk.length;

        if (received > kMaxGlbBytes) {
          debugPrint(
            '[3D DOWNLOAD][ERROR] Stream exceeded max size mid-download '
                '(received=$received, max=$kMaxGlbBytes). Aborting.',
          );
          subscription.cancel();
          if (!completer.isCompleted) {
            completer.completeError(
              StateError(
                'Downloaded model exceeds the maximum allowed size.',
              ),
            );
          }
          return;
        }

        final double p = total > 0 ? received / total : 0.0;

        debugPrint(
          '[3D DOWNLOAD] Progress: $received/${total > 0 ? total : "?"} '
              'bytes (${(p * 100).toStringAsFixed(0)}%)',
        );

        onProgress?.call(received, total > 0 ? total : received);
      },
      onDone: () {
        debugPrint('[3D DOWNLOAD] Stream finished. Total bytes: $received');
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object e, StackTrace st) {
        debugPrint('[3D DOWNLOAD][ERROR] Stream error: $e');
        debugPrint('[3D DOWNLOAD][ERROR] StackTrace:\n$st');
        if (!completer.isCompleted) completer.completeError(e, st);
      },
      cancelOnError: true,
    );

    try {
      await completer.future;
    } catch (e, st) {
      debugPrint('[3D DOWNLOAD][ERROR] Download failed mid-stream: $e');
      debugPrint('[3D DOWNLOAD][ERROR] StackTrace:\n$st');
      rethrow;
    } finally {
      await subscription.cancel();
    }

    if (bytes.isEmpty) {
      debugPrint('[3D DOWNLOAD][ERROR] Firebase returned an empty response.');
      throw StateError(
        'Firebase returned an empty response.',
      );
    }

    if (!_looksLikeGlb(bytes)) {
      final contentType =
          streamed.headers[HttpHeaders.contentTypeHeader] ?? 'unknown';

      debugPrint(
        '[3D DOWNLOAD][ERROR] Downloaded file does not look like a GLB. '
            'First 16 bytes: ${bytes.take(16).toList()} | '
            'content-type: $contentType',
      );

      throw StateError(
        'Downloaded file is not a valid GLB.\n'
            'Expected GLB magic header: glTF\n'
            'HTTP content type: '
            '$contentType',
      );
    }

    debugPrint('[3D DOWNLOAD] GLB validated.');
    debugPrint(
      '[3D DOWNLOAD] Size: '
          '${(bytes.length / 1024 / 1024).toStringAsFixed(2)} MB',
    );

    return bytes;
  }

  bool _looksLikeGlb(
      List<int> bytes,
      ) {
    if (bytes.length < 12) {
      return false;
    }

    /// ASCII "glTF"
    return bytes[0] == 0x67 &&
        bytes[1] == 0x6C &&
        bytes[2] == 0x54 &&
        bytes[3] == 0x46;
  }

  void dispose() {
    _client.close();
  }
}