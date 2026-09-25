import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';
import 'package:visionar/screens/home/model_core.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'models_list_screen.dart';

/// ===============================================================
/// FULL 3D VIEW SCREEN (RESPONSIVE + FULLSCREEN)
/// ===============================================================
/// The 3D viewer itself stays full-bleed on every platform (a 3D
/// scene wants all the space it can get), but on desktop/web the
/// scene is centered inside a wide max-width "stage" so it doesn't
/// look like a razor-thin sliver on an ultrawide monitor, and the
/// floating controls (Like button, status bar, app bar actions)
/// scale up a notch so they're comfortable to click with a mouse.
///
/// NOTE ON dart:html
/// ------------------
/// This file now imports `dart:html` directly (unconditionally) so
/// the web GLB viewer (`_WebGlbViewer` / `_GlbIframeView`) can live
/// in this same file instead of a separate conditional-import file.
/// `dart:html` only exists on the web compile target - if this exact
/// file is ever compiled for Android/iOS/desktop, the build will
/// fail at compile time on this import. Keep that in mind if this
/// codebase is ever built for non-web targets again.
///
/// NOTE ON MOBILE-WEB PERFORMANCE (UPDATED — base64 removed)
/// ------------------------------------------------------------
/// The web GLB viewer used to feed `<model-viewer>` a `data:` URI
/// built by base64-encoding the entire downloaded GLB file. Base64
/// encoding a large binary buffer (i) adds ~33% to its size and
/// (ii) is genuinely CPU-heavy to compute. On a laptop that extra
/// work is barely noticeable; on a phone's much weaker CPU, encoding
/// (and then holding in memory) a 60-150MB string on top of the
/// original bytes is exactly why the exact same model could feel
/// instant on a laptop but take a long time to "download AND
/// render" on mobile.
///
/// FIX: the raw bytes are now handed straight to a `blob:` URL
/// (`html.Blob` + `html.Url.createObjectUrlFromBlob`) with no text
/// encoding step at all - `<model-viewer>`'s `src` simply points at
/// that blob URL. This keeps the exact same benefit the base64
/// approach was introduced for (the resource never goes over the
/// network, so the browser's CORS preflight check simply does not
/// apply), while skipping the expensive encode + the ~33% memory
/// bloat entirely. See `_WebGlbViewerState.initState` and
/// `_openVrWeb` below.
///
/// NOTE ON THE VR/AR APP-BAR BUTTON
/// ------------------------------------------
/// The VR/AR button next to the QR-share button used to be hidden on
/// web entirely, because the in-app stereo WebView VR page
/// (`ModelVrStereoScreen`) depends on `LocalHttpModelServer`, which
/// needs `dart:io`'s `HttpServer` - unavailable on Flutter Web.
///
/// The button is now shown on every platform:
///   - Native (Android/iOS/desktop): unchanged, opens the in-app
///     stereo WebView VR page exactly as before.
///   - Web: tapping it opens a NEW BROWSER TAB hosting a standalone
///     `<model-viewer>` page built from the already-downloaded GLB
///     bytes (the same bytes powering the inline viewer), with the
///     `ar` attribute turned on (`ar-modes="webxr scene-viewer
///     quick-look"`). `<model-viewer>` shows its own built-in
///     "Enter AR/VR" button in that tab, which launches WebXR (or
///     Scene Viewer / Quick Look on phones) to view the model in
///     real VR/AR. It has to be a genuinely new tab (not the
///     existing embedded iframe) because some browsers block WebXR
///     session requests from a cross-origin `srcdoc`/blob iframe
///     unless it is the top-level browsing context.
/// ===============================================================

/// FULLSCREEN VIEW
/// ----------------
/// After the GLB has actually loaded, a fullscreen icon appears at the
/// bottom-right of the 3D stage. On Flutter Web it uses the browser's
/// native Fullscreen API, so desktop and mobile browsers can expand the
/// complete Flutter viewer to the screen. On Android/iOS native builds
/// it uses SystemUiMode.immersiveSticky. Press the same button again
/// (or press Esc / system back) to exit.
/// ===============================================================
///
/// /// Builds a standalone HTML page embedding Google's `<model-viewer>`
/// component, pointed at [modelSrc] (a `blob:` URL for the GLB bytes
/// we already have in memory - see the class-level note above for
/// why this is no longer a base64 `data:` URI). Shared by both the
/// inline web viewer (`_WebGlbViewer`) and the "open in a new tab to
/// enter VR/AR" button (`_ModelFullViewScreenState._openVrWeb`).
///
/// When [enableAr] is true, `<model-viewer>`'s `ar` attribute is set
/// so the page shows its own built-in "Enter AR/VR" button, which
/// launches WebXR / Scene Viewer / Quick Look depending on the
/// device.
String buildModelViewerHtml({
  required String modelSrc,
  required String title,
  bool enableAr = false,
}) {
  final safeTitle = title.replaceAll('<', '').replaceAll('>', '');

  final arAttributes = enableAr
      ? 'ar ar-modes="webxr scene-viewer quick-look" ar-scale="auto"'
      : '';

  return '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no" />
<title>$safeTitle</title>
<style>
  html, body { margin:0; padding:0; width:100%; height:100%; background:#070B10; overflow:hidden; }
  model-viewer { width:100%; height:100%; display:block; --poster-color: transparent; }
</style>
<script type="module" src="https://cdnjs.cloudflare.com/ajax/libs/model-viewer/3.4.0/model-viewer.min.js"></script>
</head>
<body>
  <model-viewer
    id="mv"
    src="$modelSrc"
    camera-controls
    auto-rotate
    loading="eager"
    reveal="auto"
    $arAttributes
    shadow-intensity="1"
    exposure="1"
    style="background-color:#070B10;">
  </model-viewer>
  <script>
    const mv = document.getElementById('mv');

    function send(msg) {
      // Posts up to the parent Flutter Web page, which listens via
      // html.window.onMessage in Dart (see _WebGlbViewerState).
      // Harmless no-op when this page is opened standalone in its
      // own tab (no parent to receive it).
      window.parent.postMessage(msg, '*');
    }

    mv.addEventListener('load', () => send('loaded'));

    mv.addEventListener('error', (e) => {
      const detail = (e && e.detail) ? JSON.stringify(e.detail) : 'unknown model-viewer error';
      send('error:' + detail);
    });

    mv.addEventListener('progress', (e) => {
      const pct = (e.detail && typeof e.detail.totalProgress === 'number')
        ? Math.round(e.detail.totalProgress * 100)
        : 0;
      send('progress:' + pct + '%');
    });

    window.addEventListener('error', (e) => {
      send('error:' + (e.message || 'window error'));
    });
  </script>
</body>
</html>
''';
}

class ModelFullViewScreen extends StatefulWidget {
  final ModelRecord model;

  const ModelFullViewScreen({
    super.key,
    required this.model,
  });

  @override
  State<ModelFullViewScreen> createState() => _ModelFullViewScreenState();
}

class _ModelFullViewScreenState extends State<ModelFullViewScreen> {
  final Flutter3DController _controller = Flutter3DController();

  final LocalHttpModelServer _localServer = LocalHttpModelServer();

  NativeGlbDownloader? _downloader;

  Future<_PreparedModel>? _prepareFuture;

  double _progress = 0.0;

  String _status = 'Preparing 3D model...';

  String? _modelHttpUrl;

  /// Web-only: holds the already-downloaded, already GLB-validated
  /// bytes once `_prepareFuture` resolves, so the VR/AR "open in new
  /// tab" button (`_openVrWeb`) can build its standalone
  /// `<model-viewer>` page without re-downloading anything. Stays
  /// null on native platforms (unused there) and while the model is
  /// still loading.
  Uint8List? _preparedWebBytes;

  /// Safety-net timer: if nothing has happened (no progress, no load,
  /// no error) after this long, we surface a clear timeout error
  /// instead of leaving the user staring at a loading spinner forever
  /// with zero feedback - which is exactly the symptom of the
  /// Android-cleartext-blocked-WebView bug this file fixes.
  ///
  /// On mobile networks/CPUs a large model genuinely can take longer
  /// than it would on a laptop, so this is intentionally generous
  /// rather than tight - it exists purely to catch a truly stuck
  /// load, not to rush a slow-but-progressing one.
  Timer? _watchdogTimer;
  static const Duration _watchdogTimeout = Duration(seconds: 60);

  /// ---- Analytics: view-time + like tracking -----------------
  /// When this screen was opened; used to compute how long the
  /// current Firebase Auth user actually looked at the model, logged
  /// to `modelViews/{modelId}` on dispose (see ModelAnalyticsService).
  DateTime? _viewStartedAt;

  StreamSubscription<dynamic>? _statsSub;
  StreamSubscription<dynamic>? _myVoteSub;

  int _likeCount = 0;
  String? _myVote; // 'like' | null

  /// FIX 10: whether this specific model allows Like at all,
  /// set by the uploader/admin at upload time. When false, the
  /// like UI is skipped entirely and no listeners are attached for
  /// it (no point subscribing to counts that can never change).
  bool get _votingEnabled => widget.model.votingEnabled;

  // ---------------------------------------------------------------
  // FULLSCREEN VIEWER
  // ---------------------------------------------------------------
  // When the model is ready, a fullscreen button is shown at the
  // bottom of the viewer. On Flutter Web it uses the browser's native
  // Fullscreen API, so it works on both desktop and mobile browsers.
  // On native Android/iOS it hides the system UI with immersiveSticky.
  bool _modelReady = false;
  bool _isFullscreen = false;
  StreamSubscription<html.Event>? _fullscreenSub;

  @override
  void initState() {
    super.initState();

    if (kIsWeb) {
      _fullscreenSub = html.document.onFullscreenChange.listen((_) {
        if (!mounted) return;
        setState(() {
          _isFullscreen = html.document.fullscreenElement != null;
        });
      });
    }

    _controller.onModelLoaded.addListener(
      _modelLoadedChanged,
    );

    _prepareFuture = _prepareModel();
    _watchPreparedFutureForWebBytes(_prepareFuture!);
    _armWatchdog();

    // Start the view-time clock as soon as the screen opens.
    _viewStartedAt = DateTime.now();

    // FIX 10: only start listening for like data if this model
    // actually allows voting - saves an unnecessary realtime
    // listener + avoids showing stale counts for a disabled model.
    if (_votingEnabled) {
      _listenAnalytics();
    }
  }

  /// Keeps `_preparedWebBytes` in sync with whatever the current
  /// `_prepareFuture` resolves to, so the VR/AR button on web always
  /// has the freshest bytes available (including after a Retry,
  /// which builds a brand new future).
  void _watchPreparedFutureForWebBytes(Future<_PreparedModel> future) {
    future.then((value) {
      if (!mounted) return;
      _preparedWebBytes = value.webBytes;
    }).catchError((_) {
      // Load errors are already surfaced by the FutureBuilder in
      // `build`; nothing extra to do here.
    });
  }

  void _armWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(_watchdogTimeout, () {
      if (!mounted) return;
      debugPrint(
        '[3D VIEW][WATCHDOG] No progress/load/error for '
            '${_watchdogTimeout.inSeconds}s. Current status: "$_status", '
            'progress: $_progress. This usually means either:\n'
            '  1) The device/emulator has no internet access, or\n'
            '  2) (Android) cleartext HTTP to 127.0.0.1 is blocked by the '
            'WebView - see network_security_config.xml + '
            'android:usesCleartextTraffic="true", or\n'
            '  3) (Web) CORS is not enabled on the Firebase Storage bucket, '
            'or the CORS preflight was rejected due to a request header '
            'not present in the bucket\'s allowed responseHeader list.',
      );
      setState(() {
        _status = 'Taking too long to load. Tap Retry, or check the '
            'debug console for the exact reason.';
      });
    });
  }

  void _listenAnalytics() {
    _statsSub =
        ModelAnalyticsService.statsStream(widget.model.id).listen((event) {
          if (!mounted) return;

          final data = event.snapshot.value;
          if (data is Map) {
            final map = Map<dynamic, dynamic>.from(data);
            setState(() {
              _likeCount = _asStatInt(map['likes']);
            });
          }
        });

    _myVoteSub =
        ModelAnalyticsService.myVoteStream(widget.model.id).listen((event) {
          if (!mounted) return;

          final data = event.snapshot.value;
          setState(() {
            _myVote = data is Map ? data['type']?.toString() : null;
          });
        });
  }

  static int _asStatInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  /// Casts (or toggles) a Like for the currently signed-in Firebase
  /// Auth user. Shows a hint if nobody is signed in, since votes are
  /// stored one-per-uid.
  ///
  /// FIX 10: also guarded by [_votingEnabled] - the button that
  /// calls this is already hidden when voting is disabled for this
  /// model, but this guard keeps the method itself safe against any
  /// stale UI/callback still holding a reference to it.
  void _castVote(String type) {
    if (!_votingEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Like is disabled for this model.'),
        ),
      );
      return;
    }

    if (ModelAnalyticsService.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You need to sign in to Like.'),
        ),
      );
      return;
    }

    unawaited(
      ModelAnalyticsService.setVote(
        modelId: widget.model.id,
        voteType: type,
      ),
    );
  }

  Future<_PreparedModel> _prepareModel() async {
    // ---- WEB PATH -------------------------------------------------
    // `dart:io`'s HttpServer (used below to re-serve the GLB from a
    // local loopback URL) does not exist on Flutter Web. See
    // `_prepareModelWeb` for the full explanation of the web
    // strategy and of the bug it fixes (model downloads to 100% but
    // never actually renders).
    if (kIsWeb) {
      return _prepareModelWeb();
    }

    _downloader = NativeGlbDownloader();

    try {
      setStateSafe(() {
        _progress = 0.0;
        _status = 'Please wait...';
      });

      final bytes = await _downloader!.download(
        model: widget.model,
        onProgress: (
            received,
            total,
            ) {
          final double p = total > 0 ? received / total : 0.0;

          setStateSafe(() {
            _progress = p.clamp(0.0, 1.0).toDouble();

            _status = total > 0
                ? 'Downloading 3D model... '
                '${(_progress * 100).toStringAsFixed(0)}%'
                : 'Downloading 3D model...';
          });

          // Any forward progress resets the "stuck" watchdog.
          _armWatchdog();
        },
      );

      setStateSafe(() {
        _progress = 1.0;
        _status = 'Starting local 3D server...';
      });

      final localUrl = await _localServer.serveGlb(
        bytes,
        fileName: widget.model.fileName ?? 'model.glb',
        modelDisplayName: widget.model.modelName,
      );

      _modelHttpUrl = localUrl;

      debugPrint(
        '[3D VIEW] Local model URL: '
            '$localUrl',
      );
      debugPrint(
        '[3D VIEW] Local VR viewer URL: '
            '${_localServer.vrViewerUrl}',
      );

      setStateSafe(() {
        _status = 'Handing local GLB to the 3D renderer...';
      });

      _armWatchdog();

      return _PreparedModel(
        localUrl: localUrl,
        sizeBytes: bytes.length,
      );
    } catch (e, stackTrace) {
      debugPrint(
        '[3D VIEW][ERROR] Prepare failed: $e',
      );
      debugPrint(
        '[3D VIEW][ERROR] StackTrace:\n$stackTrace',
      );

      rethrow;
    } finally {
      _downloader?.dispose();
      _downloader = null;
    }
  }

  /// Web preparation path.
  ///
  /// ROOT CAUSE OF THE "downloads fine but never shows on screen" BUG
  /// ------------------------------------------------------------------
  /// [NativeGlbDownloader] downloads and validates the GLB bytes just
  /// fine on web, because it only sends the `Accept` header (which is
  /// CORS-safelisted and never triggers a preflight). But handing
  /// [Flutter3DViewer] the ORIGINAL remote Firebase Storage URL makes
  /// `<model-viewer>` perform its OWN, completely separate, internal
  /// network fetch of that URL. That second fetch adds its own
  /// request headers under the hood, which the Storage bucket's CORS
  /// `responseHeader` allow-list does not include - so the preflight
  /// `OPTIONS` request gets rejected. Crucially, this failure is
  /// SILENT: `Flutter3DViewer`'s `onError` callback never fires,
  /// because the failure happens entirely inside the browser/JS
  /// layer, invisible to Dart. From the user's point of view the
  /// download bar reaches 100% and then the screen just sits there
  /// forever - until the watchdog times out.
  ///
  /// THE FIX
  /// -------
  /// We still download+validate with [NativeGlbDownloader] first - that
  /// gives a real progress bar and a hard GLB-magic-header check. But
  /// instead of handing the renderer a URL it has to fetch itself, we
  /// build a small self-contained HTML page that embeds Google's
  /// `<model-viewer>` component and points it at a `blob:` URL built
  /// directly from the bytes we ALREADY HAVE - see [_WebGlbViewer] /
  /// [_GlbIframeView]. A `blob:` URL never goes over the network, so
  /// there is no request, no preflight, and therefore no CORS to
  /// fail - and unlike the base64 `data:` URI this used to be, it
  /// needs no CPU-heavy text-encoding step, which matters a lot on
  /// slower mobile CPUs (see the file-level note near the top).
  Future<_PreparedModel> _prepareModelWeb() async {
    final url = widget.model.modelUrl.trim();

    if (url.isEmpty) {
      debugPrint('[3D VIEW][ERROR] (web) modelUrl is empty.');
      throw StateError('Firebase modelUrl is empty.');
    }

    setStateSafe(() {
      _progress = 0.0;
      _status = 'Downloading 3D model... 0%';
    });

    debugPrint('[3D VIEW] (web) Validating GLB before rendering: $url');

    final downloader = NativeGlbDownloader();
    _downloader = downloader;

    try {
      final bytes = await downloader.download(
        model: widget.model,
        onProgress: (received, total) {
          final progress = total > 0
              ? (received / total).clamp(0.0, 1.0).toDouble()
              : 0.0;

          setStateSafe(() {
            _progress = progress;
            _status = total > 0
                ? 'Downloading 3D model... ${(progress * 100).toStringAsFixed(0)}%'
                : 'Downloading 3D model...';
          });

          _armWatchdog();
        },
      );

      if (bytes.isEmpty) {
        throw StateError('Downloaded GLB is empty.');
      }

      setStateSafe(() {
        _progress = 1.0;
        _status = 'Model verified - handing to 3D renderer...';
      });

      // FIX (mobile slow load): avoid an unnecessary full copy of a
      // potentially huge buffer. `NativeGlbDownloader` already
      // returns the fully-downloaded bytes; if they're already a
      // Uint8List (the common case) we just keep the exact same
      // buffer instead of allocating and copying a second one. On a
      // memory-constrained mobile browser this copy alone could cost
      // real time and GC pressure for a large model.
      final Uint8List webBytes =
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

      if (webBytes.lengthInBytes > 150 * 1024 * 1024) {
        debugPrint(
          '[3D VIEW][WARN] (web) Model is '
              '${(webBytes.lengthInBytes / 1024 / 1024).toStringAsFixed(1)} MB. '
              'Very large models may still take a while to download and '
              'render on mobile hardware/networks no matter how they are '
              'embedded - consider a compressed (Draco / texture-optimized) '
              'export for a meaningfully faster mobile experience.',
        );
      }

      _modelHttpUrl = url; // kept only for debug logging/reference

      debugPrint(
        '[3D VIEW] (web) GLB verified: ${webBytes.length} bytes. '
            'Rendering via a blob: URL for the iframe-hosted '
            '<model-viewer> (bypasses CORS, no base64 encoding needed).',
      );

      setStateSafe(() {
        _status = 'Handing model to the 3D renderer...';
      });

      _armWatchdog();

      return _PreparedModel(
        localUrl: url,
        sizeBytes: webBytes.length,
        webBytes: webBytes,
      );
    } catch (e, stackTrace) {
      debugPrint('[3D VIEW][ERROR] Web GLB validation failed: $e');
      debugPrint('[3D VIEW][ERROR] StackTrace:\n$stackTrace');
      rethrow;
    } finally {
      downloader.dispose();
      if (identical(_downloader, downloader)) {
        _downloader = null;
      }
    }
  }

  void setStateSafe(
      VoidCallback fn,
      ) {
    if (mounted) {
      setState(fn);
    }
  }

  void _modelLoadedChanged() {
    if (!mounted) return;

    final loaded = _controller.onModelLoaded.value;

    debugPrint(
      '[3D CONTROLLER] Loaded: '
          '$loaded',
    );

    if (loaded == true) {
      _watchdogTimer?.cancel();
      setState(() {
        _progress = 1.0;
        _status = '3D model successfully loaded';
        _modelReady = true;
      });
    }
  }

  /// Toggles the 3D viewer between normal and fullscreen mode.
  ///
  /// WEB:
  /// Uses the browser Fullscreen API on the top-level document. This is
  /// preferable to trying to fullscreen the model-viewer iframe itself,
  /// because the Flutter overlay controls then remain in the same coordinate
  /// space and the feature works consistently on desktop + mobile browsers.
  ///
  /// NATIVE:
  /// Uses Flutter's immersive system UI mode. The Flutter screen itself
  /// remains the viewer, while Android/iOS status/navigation UI is hidden.
  Future<void> _toggleFullscreen() async {
    if (!mounted) return;

    try {
      if (kIsWeb) {
        final fullscreenElement = html.document.fullscreenElement;

        if (fullscreenElement != null) {
          html.document.exitFullscreen();
        } else {
          final root = html.document.documentElement;
          if (root == null) {
            throw StateError('Browser fullscreen is not available.');
          }

          root.requestFullscreen();
        }

        return;
      }

      if (_isFullscreen) {
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.edgeToEdge,
        );
      } else {
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
        );
      }

      if (!mounted) return;
      setState(() {
        _isFullscreen = !_isFullscreen;
      });
    } catch (e) {
      debugPrint('[3D VIEW][FULLSCREEN] Failed: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fullscreen mode is not available on this device.'),
          ),
        );
      }
    }
  }

  /// Always leave immersive/fullscreen mode before the viewer screen is
  /// disposed. This also handles Android back navigation and normal
  /// Navigator.pop() flows.
  Future<void> _exitFullscreenIfNeeded() async {
    try {
      if (kIsWeb) {
        if (html.document.fullscreenElement != null) {
          html.document.exitFullscreen();
        }
        return;
      }

      if (_isFullscreen) {
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.edgeToEdge,
        );
      }
    } catch (e) {
      debugPrint('[3D VIEW][FULLSCREEN] Restore UI failed: $e');
    }
  }

  Future<void> _retry() async {
    if (!mounted) return;

    debugPrint('[3D VIEW] Retry requested by user.');

    await _localServer.stop();

    late final Future<_PreparedModel> newFuture;

    setState(() {
      _progress = 0.0;
      _status = 'Retrying 3D model...';

      _modelReady = false;
      _modelHttpUrl = null;
      _preparedWebBytes = null;

      newFuture = _prepareModel();
      _prepareFuture = newFuture;
    });

    _watchPreparedFutureForWebBytes(newFuture);
    _armWatchdog();
  }

  /// Opens the VR/AR experience for this model.
  ///
  /// - Native (Android/iOS/desktop): pushes the in-app stereo
  ///   WebView VR screen, served by [LocalHttpModelServer] - exactly
  ///   as before.
  /// - Web: opens a brand-new browser tab hosting a standalone
  ///   `<model-viewer>` page (built from the bytes already
  ///   downloaded for the inline viewer) with AR/VR enabled, so the
  ///   user can tap `<model-viewer>`'s own "Enter AR/VR" button to
  ///   launch WebXR / Scene Viewer / Quick Look.
  void _openVr() {
    if (kIsWeb) {
      final bytes = _preparedWebBytes;

      if (bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The model is not ready yet. Please wait a moment and try again.',
            ),
          ),
        );
        return;
      }

      _openVrWeb(bytes);
      return;
    }

    final vrUrl = _localServer.vrViewerUrl;

    if (vrUrl == null || !_localServer.isRunning) {
      debugPrint('[3D VIEW][ERROR] _openVr called but local server not ready.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The model is not ready yet. Please wait a moment and try again.',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ModelVrStereoScreen(
          vrUrl: vrUrl,
          modelName: widget.model.modelName,
        ),
      ),
    );
  }

  /// Web-only: builds a standalone AR/VR-enabled `<model-viewer>`
  /// page from [bytes] and opens it in a new browser tab via a Blob
  /// URL. Opening a genuinely new top-level tab (rather than reusing
  /// the existing embedded iframe) matters because some browsers
  /// refuse to grant a WebXR session to a page loaded inside a
  /// cross-origin `blob:`/`srcdoc` iframe unless it is the top-level
  /// browsing context.
  ///
  /// FIX (mobile slow open): points `<model-viewer>` at a `blob:` URL
  /// built directly from the raw bytes instead of base64-encoding
  /// them into a `data:` URI first - same CORS-bypass benefit,
  /// without the expensive encode step (see file-level note above).
  void _openVrWeb(Uint8List bytes) {
    final modelBlob = html.Blob(<Object>[bytes], 'model/gltf-binary');
    final modelBlobUrl = html.Url.createObjectUrlFromBlob(modelBlob);

    final htmlContent = buildModelViewerHtml(
      modelSrc: modelBlobUrl,
      title: widget.model.modelName,
      enableAr: true,
    );

    final pageBlob = html.Blob(<Object>[htmlContent], 'text/html');
    final pageBlobUrl = html.Url.createObjectUrlFromBlob(pageBlob);

    debugPrint(
      '[3D VIEW] (web) Opening AR/VR viewer in a new tab for '
          '"${widget.model.modelName}".',
    );

    html.window.open(pageBlobUrl, '_blank');

    // The new tab holds its own reference to both blob URLs via the
    // page it navigated to; revoking slightly later (rather than
    // immediately) avoids a race where some browsers haven't
    // finished navigating to it yet.
    Timer(const Duration(seconds: 30), () {
      html.Url.revokeObjectUrl(pageBlobUrl);
      html.Url.revokeObjectUrl(modelBlobUrl);
    });
  }

  /// FIX 12: opens the QR-code / shareable-link screen for this
  /// model, so it can be opened on ANY other device (or in a
  /// desktop browser) by scanning the QR code or tapping the link -
  /// no app install needed and, unlike hitting the raw Firebase
  /// modelUrl directly, the link RENDERS the model instead of
  /// triggering a file download.
  void _openQrShare() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ModelQrShareScreen(model: widget.model),
      ),
    );
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();

    _controller.onModelLoaded.removeListener(
      _modelLoadedChanged,
    );

    // ---- Analytics: log this viewing session's duration ------------
    _statsSub?.cancel();
    _myVoteSub?.cancel();

    final viewStartedAt = _viewStartedAt;
    if (viewStartedAt != null) {
      final durationSeconds =
          DateTime.now().difference(viewStartedAt).inSeconds;

      unawaited(
        ModelAnalyticsService.logViewSession(
          modelId: widget.model.id,
          startedAt: viewStartedAt,
          durationSeconds: durationSeconds,
        ),
      );
    }

    // On web the local server was never started, so this is a
    // harmless no-op there.
    unawaited(
      _localServer.stop(),
    );

    _downloader?.dispose();

    _fullscreenSub?.cancel();
    unawaited(_exitFullscreenIfNeeded());

    super.dispose();
  }

  @override
  Widget build(
      BuildContext context,
      ) {
    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isFullscreen) {
          unawaited(_toggleFullscreen());
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF070B10),
        appBar: _isFullscreen
            ? null
            : AppBar(
          backgroundColor: const Color(0xFF070B10),
          elevation: 0,
          title: Text(
            widget.model.modelName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            // AR/VR (goggles-style) button - shown on every platform,
            // right next to the QR-share button. On native it opens
            // the in-app stereo WebView VR page; on web it opens a new
            // tab with an AR/VR-enabled <model-viewer> page (see
            // `_openVr` / `_openVrWeb`).
            IconButton(
              tooltip: 'View in AR/VR',
              onPressed: _openVr,
              icon: Image.asset(
                'assets/vr_icon.png',
                width: 28,
                height: 28,
                fit: BoxFit.contain,
              ),
            ),
            // QR / shareable-link button.
            IconButton(
              tooltip: 'Share QR Code',
              onPressed: _openQrShare,
              icon: const Icon(
                Icons.qr_code_2,
                color: Colors.white70,
              ),
            ),
          ],
        ),
        // ---------------------------------------------------------------
        // FIX 7: the body is now a Column instead of a Stack +
        // Positioned.fill. The 3D viewer is confined to the Expanded
        // (top) area; the status bar sits BELOW it as a separate solid
        // strip. So the model can never render below the status bar's
        // top line - which was the issue seen in the screenshot, and is
        // now fixed here.
        // ---------------------------------------------------------------
        body: FutureBuilder<_PreparedModel>(
          future: _prepareFuture,
          builder: (
              context,
              snapshot,
              ) {
            if (snapshot.connectionState != ConnectionState.done) {
              return _LoadingState(
                progress: _progress,
                message: _status,
              );
            }

            if (snapshot.hasError || snapshot.data == null) {
              debugPrint(
                '[3D VIEW][ERROR] FutureBuilder surfaced error: '
                    '${snapshot.error}',
              );
              return _ErrorState(
                error: snapshot.error,
                onRetry: _retry,
              );
            }

            final prepared = snapshot.data!;

            debugPrint(
              '[3D VIEW] Feeding URL to '
                  'Flutter3DViewer: '
                  '${prepared.localUrl}',
            );

            return LayoutBuilder(
              builder: (context, constraints) {
                final deviceType = deviceTypeOf(constraints.maxWidth);

                // FIX 8: the bottom mask height is fixed and known
                // ahead of time (status bar content + its padding +
                // bottom safe-area inset), so we can reserve exactly
                // that much space and paint an opaque strip over it,
                // regardless of what the native 3D surface underneath
                // does. Slightly taller on desktop/web where fonts and
                // touch targets are a notch bigger.
                final double bottomSafeInset =
                    MediaQuery.of(context).padding.bottom;
                final double statusBarContentHeight =
                deviceType.isDesktop ? 48.0 : 44.0;
                const double statusBarVerticalPadding = 24.0; // 12 + 12
                final double maskHeight = statusBarContentHeight +
                    statusBarVerticalPadding +
                    bottomSafeInset;

                // Desktop/web: keep the 3D scene inside a wide but
                // bounded "stage" so it never turns into a razor-thin
                // sliver on an ultrawide monitor; mobile/tablet stay
                // full-bleed like before.
                final double stageMaxWidth =
                deviceType.isDesktop ? 1700.0 : double.infinity;

                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: stageMaxWidth),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // ---- 3D VIEWER (fills the stage) -------------
                        // FIX (CORS root cause + mobile perf): on web,
                        // Flutter3DViewer's internal cross-origin fetch
                        // to Firebase Storage was silently blocked by
                        // the browser's CORS preflight (no onError ever
                        // fired - just the watchdog timeout). We already
                        // have validated bytes in memory (see
                        // `_prepareModelWeb`), so on web we render via an
                        // iframe hosting our own <model-viewer> page fed
                        // a blob: URL (no base64, see
                        // `_WebGlbViewerState`), which needs no network
                        // fetch at all. Native platforms
                        // (Android/iOS/desktop) keep using
                        // Flutter3DViewer + the local loopback HTTP
                        // server exactly as before - completely
                        // unchanged.
                        if (kIsWeb && prepared.webBytes != null)
                          _WebGlbViewer(
                            key: ValueKey('web-${widget.model.id}'),
                            bytes: prepared.webBytes!,
                            modelName: widget.model.modelName,
                            onStatus: (msg) {
                              if (!mounted) return;
                              setState(() {
                                _status = 'Rendering 3D model... $msg';
                              });
                              _armWatchdog();
                            },
                            onLoaded: () {
                              if (!mounted) return;
                              _watchdogTimer?.cancel();
                              setState(() {
                                _progress = 1.0;
                                _status = '3D model successfully loaded';
                                _modelReady = true;
                              });
                            },
                            onError: (err) {
                              if (!mounted) return;
                              debugPrint(
                                '[3D VIEW][ERROR] Web renderer error: $err',
                              );
                              setState(() {
                                _status =
                                '3D renderer error - see debug console for details ($err)';
                              });
                            },
                          )
                        else
                          Flutter3DViewer(
                            key: ValueKey(
                              prepared.localUrl,
                            ),
                            src: prepared.localUrl,
                            controller: _controller,
                            activeGestureInterceptor: true,
                            enableTouch: true,
                            progressBarColor: Colors.white,
                            onProgress: (
                                double progressValue,
                                ) {
                              if (!mounted) return;

                              debugPrint(
                                '[3D VIEW] Renderer progress: '
                                    '${(progressValue * 100).toStringAsFixed(0)}%',
                              );

                              setState(() {
                                _progress =
                                    progressValue.clamp(0.0, 1.0).toDouble();

                                _status = 'Rendering 3D model... '
                                    '${(_progress * 100).toStringAsFixed(0)}%';
                              });

                              _armWatchdog();
                            },
                            onLoad: (
                                String modelAddress,
                                ) {
                              debugPrint(
                                '[3D VIEW] onLoad: '
                                    '$modelAddress',
                              );

                              if (!mounted) return;

                              _watchdogTimer?.cancel();

                              setState(() {
                                _status = '3D model ready';
                                _modelReady = true;
                                _progress = 1.0;
                              });
                            },
                            onError: (
                                String error,
                                ) {
                              debugPrint(
                                '[3D VIEW][ERROR] Renderer onError: '
                                    '$error',
                              );

                              if (!mounted) return;

                              setState(() {
                                _status = '3D renderer error - see debug '
                                    'console for details ($error)';
                              });
                            },
                          ),

                        // ---- Floating Like button (top-right) --------
                        // FIX 10: skipped entirely when the model owner
                        // has disabled voting for this model.
                        if (_votingEnabled)
                          Positioned(
                            top: 12,
                            right: 12,
                            child: SafeArea(
                              bottom: false,
                              child: _HeartLikeButton(
                                count: _likeCount,
                                active: _myVote == 'like',
                                onPressed: () => _castVote('like'),
                                scaleUp: deviceType.isDesktop,
                              ),
                            ),
                          ),

                        // ---- FULLSCREEN BUTTON -----------------------
                        // Only appears after the model has actually loaded.
                        // It sits just above the status strip in normal mode
                        // and at the bottom edge in fullscreen mode.
                        if (_modelReady)
                          Positioned(
                            right: deviceType.isDesktop ? 24 : 16,
                            bottom: _isFullscreen ? 20 : maskHeight + 12,
                            child: SafeArea(
                              top: false,
                              left: false,
                              right: false,
                              bottom: false,
                              child: Material(
                                color: const Color(0xCC151C24),
                                shape: const CircleBorder(),
                                elevation: 8,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _toggleFullscreen,
                                  child: Padding(
                                    padding: EdgeInsets.all(
                                      deviceType.isDesktop ? 13 : 12,
                                    ),
                                    child: Icon(
                                      _isFullscreen
                                          ? Icons.fullscreen_exit_rounded
                                          : Icons.fullscreen_rounded,
                                      color: Colors.white,
                                      size: deviceType.isDesktop ? 25 : 23,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // ---- FIX 8: OPAQUE bottom mask, drawn LAST so
                        // it always paints on top of the 3D surface
                        // below it - nothing from the model (even if
                        // the native renderer bleeds past its own
                        // bounds) can show through this. --
                        if (!_isFullscreen)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: maskHeight,
                            child: IgnorePointer(
                              ignoring: false,
                              child: Material(
                                color: const Color(0xFF0B0F14),
                                child: SafeArea(
                                  top: false,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: deviceType.isDesktop ? 24 : 12,
                                      vertical: 12,
                                    ),
                                    child: Center(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: deviceType.isDesktop
                                              ? 900
                                              : double.infinity,
                                        ),
                                        child: _StatusBar(
                                          status: _status,
                                          progress: _progress,
                                          sizeBytes: prepared.sizeBytes,
                                          deviceType: deviceType,
                                        ),
                                      ),
                                    ),
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
      ),
    );
  }
}

class _PreparedModel {
  final String localUrl;
  final int sizeBytes;

  /// Only populated on web (kIsWeb == true). Holds the already
  /// downloaded, already GLB-magic-header-validated bytes so they can
  /// be turned directly into a `blob:` URL for the iframe-hosted
  /// <model-viewer> page (see [_WebGlbViewer]), and reused to open
  /// the AR/VR "new tab" viewer (see
  /// [_ModelFullViewScreenState._openVrWeb]). This completely
  /// bypasses the browser CORS preflight that otherwise silently
  /// breaks Flutter3DViewer's own internal fetch on web, with no
  /// base64 text-encoding step in between (see the file-level note
  /// near the top for why that matters especially on mobile).
  final Uint8List? webBytes;

  const _PreparedModel({
    required this.localUrl,
    required this.sizeBytes,
    this.webBytes,
  });
}

/// ===============================================================
/// WEB-ONLY GLB VIEWER (fixes the CORS black-screen bug, the
/// `setJavaScriptMode is not implemented on the current platform`
/// crash, AND the slow-on-mobile base64 overhead)
/// ===============================================================
/// `webview_flutter` has NO web implementation registered in this
/// project, so calling `WebViewController()` on the web target throws
/// `UnimplementedError` at `setJavaScriptMode`. Rather than depend on
/// webview_flutter on web at all, this renders the model via a plain
/// HTML `<iframe>` embedded through `HtmlElementView` +
/// `ui_web.platformViewRegistry` - a core Flutter Web capability that
/// needs no extra plugin.
///
/// The iframe's `src` is a Blob URL (not `srcdoc`) so it can host an
/// arbitrarily large page; the model itself is ALSO referenced via
/// its own separate `blob:` URL (see `_modelBlobUrl` below) rather
/// than being embedded as base64 text inside that page - this is the
/// fix for the "fine on laptop, slow on mobile" issue, since it
/// skips the CPU-heavy base64 encode step entirely (see the
/// file-level note near the top of this file for the full
/// explanation).
///
/// Since the iframe is a separate browsing context, we can't use a
/// JS-channel the way `addJavaScriptChannel` worked with
/// webview_flutter. Instead the embedded page posts messages with
/// `window.parent.postMessage(...)`, and we listen for those via
/// `html.window.onMessage` here in Dart.
///
/// Only ever constructed when `kIsWeb` is true (see
/// `_ModelFullViewScreenState.build`) - on Android/iOS/desktop the
/// existing Flutter3DViewer + local HTTP server path is used exactly
/// as before, completely unchanged.
/// ===============================================================

class _WebGlbViewer extends StatefulWidget {
  final Uint8List bytes;
  final String modelName;
  final ValueChanged<String>? onStatus;
  final VoidCallback? onLoaded;
  final ValueChanged<String>? onError;

  const _WebGlbViewer({
    super.key,
    required this.bytes,
    required this.modelName,
    this.onStatus,
    this.onLoaded,
    this.onError,
  });

  @override
  State<_WebGlbViewer> createState() => _WebGlbViewerState();
}

class _WebGlbViewerState extends State<_WebGlbViewer> {
  late final String _html;

  /// The GLB file's own blob URL (separate from the outer HTML page's
  /// blob URL, which `_GlbIframeView` manages). Must be revoked when
  /// this widget is disposed, or the browser keeps the (potentially
  /// huge) buffer pinned in memory indefinitely.
  String? _modelBlobUrl;

  @override
  void initState() {
    super.initState();

    // FIX (mobile slow load/render): previously this base64-encoded
    // `widget.bytes` into a `data:` URI and embedded that giant
    // string directly inside the HTML page. Base64-encoding a large
    // binary buffer adds ~33% to its size and is genuinely CPU-heavy
    // to compute - fine on a laptop's CPU, noticeably slower on a
    // phone's. Now we skip that step completely: a `blob:` URL is
    // just a reference to the existing bytes, no text encoding at
    // all, and `<model-viewer>`'s `src` points straight at it.
    final modelBlob = html.Blob(<Object>[widget.bytes], 'model/gltf-binary');
    _modelBlobUrl = html.Url.createObjectUrlFromBlob(modelBlob);

    debugPrint(
      '[WEB VIEWER] Built blob URL for "${widget.modelName}": '
          '$_modelBlobUrl (${widget.bytes.lengthInBytes} bytes, '
          'no base64 encoding needed)',
    );

    // NOTE: this inline embedded viewer intentionally does NOT enable
    // `ar` (enableAr: false, the default) - WebXR session requests
    // from inside this blob-backed iframe are unreliable across
    // browsers. The dedicated "Enter AR/VR" flow instead opens a
    // brand-new top-level tab built from this same helper with
    // `enableAr: true` - see
    // `_ModelFullViewScreenState._openVrWeb`.
    _html = buildModelViewerHtml(
      modelSrc: _modelBlobUrl!,
      title: widget.modelName,
    );
  }

  void _handleBridgeMessage(String data) {
    debugPrint('[WEB VIEWER] Bridge message: $data');

    if (data == 'loaded') {
      widget.onLoaded?.call();
    } else if (data.startsWith('error:')) {
      widget.onError?.call(data.substring(6));
    } else if (data.startsWith('progress:')) {
      widget.onStatus?.call(data.substring(9));
    }
  }

  @override
  void dispose() {
    final modelBlobUrl = _modelBlobUrl;
    if (modelBlobUrl != null) {
      html.Url.revokeObjectUrl(modelBlobUrl);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _GlbIframeView(
      htmlContent: _html,
      onMessage: _handleBridgeMessage,
    );
  }
}

/// Low-level iframe host. Registers a platform-view factory that
/// creates an `<iframe>` pointed at a Blob URL built from the given
/// HTML string, and forwards `window.onMessage` events (posted by the
/// embedded page via `window.parent.postMessage`) to [onMessage].
///
/// The HTML string itself is now small (it only contains a `blob:`
/// URL reference, not a multi-megabyte base64 string), so wrapping it
/// in this outer blob is cheap regardless of how large the actual GLB
/// model is.
class _GlbIframeView extends StatefulWidget {
  final String htmlContent;
  final void Function(String message) onMessage;

  const _GlbIframeView({
    required this.htmlContent,
    required this.onMessage,
  });

  @override
  State<_GlbIframeView> createState() => _GlbIframeViewState();
}

class _GlbIframeViewState extends State<_GlbIframeView> {
  late final String _viewType;
  String? _blobUrl;
  StreamSubscription<html.MessageEvent>? _messageSub;

  @override
  void initState() {
    super.initState();

    _viewType = 'glb-viewer-${identityHashCode(this)}-'
        '${DateTime.now().microsecondsSinceEpoch}';

    // A Blob URL avoids the size limits some browsers impose on the
    // `srcdoc` attribute. The HTML itself is small now (it just
    // references the model's own separate blob: URL), but a blob URL
    // is still the simplest way to host an isolated document for the
    // iframe.
    final blob = html.Blob(<Object>[widget.htmlContent], 'text/html');
    _blobUrl = html.Url.createObjectUrlFromBlob(blob);

    final iframe = html.IFrameElement()
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow = 'accelerometer; gyroscope; xr-spatial-tracking; fullscreen'
      ..allowFullscreen = true
      ..src = _blobUrl;

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
          (int viewId) => iframe,
    );

    // The iframe is a separate document, so there's no equivalent of
    // webview_flutter's `addJavaScriptChannel`. Instead, the embedded
    // page's own script does `window.parent.postMessage(...)`, and we
    // listen for that here.
    _messageSub = html.window.onMessage.listen((event) {
      final data = event.data;
      if (data is String) {
        widget.onMessage(data);
      }
    });
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    final blobUrl = _blobUrl;
    if (blobUrl != null) {
      html.Url.revokeObjectUrl(blobUrl);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}

/// ===============================================================
/// IN-APP STEREO VR SCREEN
/// Hosts the split-screen /viewer.html inside a WebView. Forces
/// landscape + immersive full-screen while active (matches how the
/// phone sits inside a lens headset) ONLY on Android/iOS - on web
/// and desktop, orientation locking either doesn't apply or isn't
/// supported, so those calls are skipped there and the WebView is
/// simply shown as-is, full screen, inside whatever window size the
/// user already has. Everything is restored on exit.
/// All of the actual controls (Move Up/Down, Zoom In/Out, Auto
/// Rotate, Play/Pause, Reset) live inside the HTML page itself
/// (FIX 4 / FIX 5) - this Flutter screen just hosts the WebView and
/// the exit button.
///
/// This screen itself is only ever navigated to on non-web platforms
/// (see `_openVr` above), since it's fed a `vrUrl` produced by
/// [LocalHttpModelServer], which does not run on Flutter Web. On
/// web, `_openVr` instead opens a new browser tab (see
/// `_openVrWeb`).
/// ===============================================================

class ModelVrStereoScreen extends StatefulWidget {
  final String vrUrl;
  final String modelName;

  const ModelVrStereoScreen({
    super.key,
    required this.vrUrl,
    required this.modelName,
  });

  @override
  State<ModelVrStereoScreen> createState() => _ModelVrStereoScreenState();
}

class _ModelVrStereoScreenState extends State<ModelVrStereoScreen> {
  late final WebViewController _webViewController;

  bool _hasError = false;

  @override
  void initState() {
    super.initState();

    unawaited(_enterImmersiveLandscape());

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const
      Color(0xFF000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            debugPrint('[VR WEBVIEW][ERROR] ${error.description}');
            debugPrint(
              '[VR WEBVIEW][ERROR] errorCode=${error.errorCode} '
                  'errorType=${error.errorType}',
            );
            if (mounted) {
              setState(() {
                _hasError = true;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.vrUrl));
  }

  Future<void> _enterImmersiveLandscape() async {
    // Orientation locking + immersive system UI are mobile-only
    // concepts - skip them entirely on web/desktop where there's no
    // "landscape lock" to apply and the calls would either no-op or
    // throw.
    if (!isMobilePlatform) return;

    await SystemChrome.setPreferredOrientations(
      <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    );
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );
  }

  Future<void> _restoreNormalUi() async {
    if (!isMobilePlatform) return;

    await SystemChrome.setPreferredOrientations(
      <DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ],
    );
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );
  }

  Future<void> _exitVr() async {
    await _restoreNormalUi();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    unawaited(_restoreNormalUi());
    super.dispose();
  }

  @override
  Widget build(
      BuildContext context,
      ) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          unawaited(_restoreNormalUi());
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final deviceType = deviceTypeOf(constraints.maxWidth);

            // On a wide desktop/web window there's no physical
            // "goggles" to fill edge-to-edge, so the stereo view is
            // kept at a sane max width and centered instead of
            // stretching the two eye-views far apart.
            final double stageMaxWidth =
            deviceType.isDesktop ? 1400.0 : double.infinity;

            return Stack(
              children: [
                Positioned.fill(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: stageMaxWidth),
                      child: WebViewWidget(
                        controller: _webViewController,
                      ),
                    ),
                  ),
                ),
                if (_hasError)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.redAccent,
                                size: 48,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'VR view failed to load',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _exitVr,
                                icon: const Icon(Icons.arrow_back),
                                label: const Text('Go back'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: SafeArea(
                    child: Material(
                      color: const Color(0x99151C24),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _exitVr,
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
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
/// UI HELPERS (loading / status bar / like button / error state)
/// ===============================================================

/// Circular progress loader shown while the model downloads /
/// prepares: a ring with a live "NN%" label in the middle, the
/// status message below it, and an animated "Loading...." caption
/// with dots that cycle so the screen never looks frozen.
class _LoadingState extends StatefulWidget {
  final double progress;
  final String message;

  const _LoadingState({
    required this.progress,
    required this.message,
  });

  @override
  State<_LoadingState> createState() => _LoadingStateState();
}

class _LoadingStateState extends State<_LoadingState> {
  Timer? _dotTimer;
  int _dotCount = 0;

  @override
  void initState() {
    super.initState();
    _dotTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (!mounted) return;
      setState(() {
        _dotCount = (_dotCount + 1) % 6; // cycles 0..5 dots
      });
    });
  }

  @override
  void dispose() {
    _dotTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dots = '.' * (_dotCount + 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final deviceType = deviceTypeOf(constraints.maxWidth);
        final ringSize = deviceType.isDesktop ? 140.0 : 116.0;

        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 28,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: ringSize,
                  height: ringSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: ringSize,
                        height: ringSize,
                        child: CircularProgressIndicator(
                          // A `value` of exactly 0 renders as an empty
                          // ring that can look like "nothing is
                          // happening". Passing `null` whenever we
                          // don't have a real fraction yet makes it an
                          // indeterminate spinner instead, which is a
                          // much clearer "still working" signal.
                          value: widget.progress > 0
                              ? widget.progress.clamp(0.0, 1.0)
                              : null,
                          strokeWidth: 7,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF2F86FF),
                          ),
                        ),
                      ),
                      if (widget.progress > 0)
                        Text(
                          '${(widget.progress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: deviceType.isDesktop ? 16 : 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 18,
                  child: Text(
                    'Loading$dots',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusBar extends StatelessWidget {
  final String status;
  final double progress;
  final int sizeBytes;
  final DeviceType deviceType;

  const _StatusBar({
    required this.status,
    required this.progress,
    required this.sizeBytes,
    required this.deviceType,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    // sizeBytes now reflects the validated download size on web too
    // (see `_prepareModelWeb`), so this suffix is accurate on every
    // platform.
    final sizeMb = sizeBytes / 1024 / 1024;
    final sizeSuffix =
    sizeBytes > 0 ? '  •  ${sizeMb.toStringAsFixed(1)} MB' : '';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xDD111820),
        borderRadius: BorderRadius.circular(
          10,
        ),
        border: Border.all(
          color: Colors.white12,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(
          10,
        ),
        child: Row(
          children: [
            Icon(
              Icons.check_circle,
              color: Colors.greenAccent,
              size: deviceType.isDesktop ? 21 : 19,
            ),
            const SizedBox(
              width: 8,
            ),
            Expanded(
              child: Text(
                '$status$sizeSuffix',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: deviceType.isDesktop ? 13 : 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Heart-shaped Like button with a small "pop" bounce animation
/// every time it's tapped, and a live count next to it. Turns solid
/// red + filled heart when this model reflects the current user's
/// own like. `scaleUp` gives it a slightly larger hit target/text on
/// desktop/web, where it's clicked with a mouse rather than tapped.
class _HeartLikeButton extends StatefulWidget {
  final int count;
  final bool active;
  final VoidCallback onPressed;
  final bool scaleUp;

  const _HeartLikeButton({
    required this.count,
    required this.active,
    required this.onPressed,
    this.scaleUp = false,
  });

  @override
  State<_HeartLikeButton> createState() => _HeartLikeButtonState();
}

class _HeartLikeButtonState extends State<_HeartLikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceController;
  late final Animation<double> _bounceScale;

  @override
  void initState() {
    super.initState();

    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    _bounceScale = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.45), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.45, end: 0.9), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 30),
    ]).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  void _handleTap() {
    _bounceController.forward(from: 0);
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.scaleUp ? 21.0 : 19.0;
    final fontSize = widget.scaleUp ? 14.0 : 13.0;
    final horizontalPad = widget.scaleUp ? 16.0 : 13.0;
    final verticalPad = widget.scaleUp ? 11.0 : 9.0;

    return Tooltip(
      message: widget.active ? 'Unlike' : 'Like',
      child: Material(
        color: widget.active
            ? const Color(0xFFE0245E)
            : const Color(0xDD151C24),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: _handleTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPad,
              vertical: verticalPad,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _bounceScale,
                  child: Icon(
                    widget.active ? Icons.favorite : Icons.favorite_border,
                    color: widget.active ? Colors.white : Colors.white70,
                    size: iconSize,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${widget.count}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(
          24,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 68,
              ),
              const SizedBox(
                height: 18,
              ),
              const Text(
                '3D model failed to load',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(
                height: 10,
              ),
              Text(
                error?.toString() ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                ),
              ),
              const SizedBox(
                height: 6,
              ),
              const Text(
                'Full details were also printed to the debug console.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(
                height: 20,
              ),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(
                  Icons.refresh,
                ),
                label: const Text(
                  'Retry',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
