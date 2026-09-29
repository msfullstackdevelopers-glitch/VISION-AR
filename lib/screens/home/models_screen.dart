import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:visionar/screens/home/model_core.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'models_list_screen.dart';

/// ===============================================================
/// FULL 3D VIEW SCREEN (RESPONSIVE + FULLSCREEN)
/// ===============================================================
/// NEW in this version
/// -------------------
/// 1. FULLSCREEN button (AppBar, enabled only after the model has
///    loaded). Tapping it:
///      - hides the AppBar + bottom status bar,
///      - lets the 3D scene fill the entire screen (no max-width
///        stage), and
///      - on web asks the browser for REAL fullscreen through the
///        Fullscreen API (desktop + Android). iOS Safari does not
///        support this for normal pages, so there the layout still
///        fills the whole viewport (in-app fullscreen fallback).
/// 2. CLOSE (X) button, top-left, visible only while fullscreen.
///    Also: browser Esc key and the system Back button exit
///    fullscreen first (instead of leaving the screen).
/// 3. CLICK FIX: on Flutter Web the 3D scene is an HTML <iframe>
///    (platform view). A platform view swallows every mouse event
///    that lands on it, even when a Flutter widget is painted above
///    it - so the Like / Close buttons "looked" fine but the cursor
///    click never reached them. Every floating control is now
///    wrapped in `PointerInterceptor` which fixes exactly that.
///
/// REQUIRED pubspec.yaml dependency:
///     pointer_interceptor: ^0.10.1
///
/// NOTE ON dart:html: this file imports dart:html unconditionally,
/// so it only compiles for the web target.
/// ===============================================================

/// Builds a standalone HTML page embedding Google's `<model-viewer>`
/// pointed at [modelSrc] (a `blob:` URL - no base64 needed).
/// When [enableAr] is true the built-in "Enter AR/VR" button shows.
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

  /// Web-only: validated GLB bytes, reused by the AR/VR new-tab button.
  Uint8List? _preparedWebBytes;

  /// True once the model has been prepared successfully. The
  /// fullscreen button is disabled until this is true.
  bool _isReady = false;

  /// True while the 3D view is in fullscreen mode.
  bool _isFullscreen = false;

  StreamSubscription<html.Event>? _fullscreenSub;

  Timer? _watchdogTimer;
  static const Duration _watchdogTimeout = Duration(seconds: 60);

  /// ---- Analytics: view-time + like tracking -----------------
  DateTime? _viewStartedAt;

  StreamSubscription<dynamic>? _statsSub;
  StreamSubscription<dynamic>? _myVoteSub;

  int _likeCount = 0;
  String? _myVote; // 'like' | null

  bool get _votingEnabled => widget.model.votingEnabled;

  @override
  void initState() {
    super.initState();

    _controller.onModelLoaded.addListener(
      _modelLoadedChanged,
    );

    _prepareFuture = _prepareModel();
    _watchPreparedFuture(_prepareFuture!);
    _armWatchdog();

    _viewStartedAt = DateTime.now();

    if (_votingEnabled) {
      _listenAnalytics();
    }

    // Keeps our state in sync when the browser leaves fullscreen on
    // its own (Esc key, F11, swipe gesture on mobile, etc).
    if (kIsWeb) {
      _fullscreenSub = html.document.onFullscreenChange.listen((_) {
        final stillFullscreen = html.document.fullscreenElement != null;
        if (!stillFullscreen && _isFullscreen && mounted) {
          setState(() {
            _isFullscreen = false;
          });
        }
      });
    }
  }

  /// Tracks the prepare future: stores web bytes for the AR/VR button
  /// and flips [_isReady] so the fullscreen button becomes usable.
  void _watchPreparedFuture(Future<_PreparedModel> future) {
    future.then((value) {
      if (!mounted) return;
      setState(() {
        _preparedWebBytes = value.webBytes;
        _isReady = true;
      });
    }).catchError((_) {
      // Errors are shown by the FutureBuilder in `build`.
    });
  }

  // ---------------------------------------------------------------
  // FULLSCREEN
  // ---------------------------------------------------------------

  /// Enters fullscreen. `requestFullscreen()` must run synchronously
  /// inside the tap handler (browsers require a user gesture), so it
  /// is called before any `await`.
  void _enterFullscreen() {
    if (_isFullscreen || !_isReady) return;

    if (kIsWeb) {
      try {
        html.document.documentElement?.requestFullscreen();
      } catch (e) {
        // e.g. iOS Safari - we still show the in-app fullscreen layout.
        debugPrint('[3D VIEW] Browser fullscreen not available: $e');
      }
    } else {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    }

    setState(() {
      _isFullscreen = true;
    });
  }

  void _exitFullscreen() {
    if (!_isFullscreen) return;

    if (kIsWeb) {
      try {
        if (html.document.fullscreenElement != null) {
          html.document.exitFullscreen();
        }
      } catch (e) {
        debugPrint('[3D VIEW] exitFullscreen failed: $e');
      }
    } else {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }

    if (mounted) {
      setState(() {
        _isFullscreen = false;
      });
    }
  }

  void _toggleFullscreen() {
    if (_isFullscreen) {
      _exitFullscreen();
    } else {
      _enterFullscreen();
    }
  }

  // ---------------------------------------------------------------

  void _armWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(_watchdogTimeout, () {
      if (!mounted) return;
      debugPrint(
        '[3D VIEW][WATCHDOG] No progress/load/error for '
            '${_watchdogTimeout.inSeconds}s. Status: "$_status", '
            'progress: $_progress. Possible causes: no internet, blocked '
            'cleartext HTTP (Android WebView), or CORS on the storage bucket.',
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
        onProgress: (received, total) {
          final double p = total > 0 ? received / total : 0.0;

          setStateSafe(() {
            _progress = p.clamp(0.0, 1.0).toDouble();

            _status = total > 0
                ? 'Downloading 3D model... '
                '${(_progress * 100).toStringAsFixed(0)}%'
                : 'Downloading 3D model...';
          });

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

      debugPrint('[3D VIEW] Local model URL: $localUrl');
      debugPrint('[3D VIEW] Local VR viewer URL: ${_localServer.vrViewerUrl}');

      setStateSafe(() {
        _status = 'Handing local GLB to the 3D renderer...';
      });

      _armWatchdog();

      return _PreparedModel(
        localUrl: localUrl,
        sizeBytes: bytes.length,
      );
    } catch (e, stackTrace) {
      debugPrint('[3D VIEW][ERROR] Prepare failed: $e');
      debugPrint('[3D VIEW][ERROR] StackTrace:\n$stackTrace');
      rethrow;
    } finally {
      _downloader?.dispose();
      _downloader = null;
    }
  }

  /// Web path: download + validate the GLB, then render it through an
  /// iframe hosting `<model-viewer>` fed by a `blob:` URL (no network
  /// fetch => no CORS preflight, and no slow base64 encoding).
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

      final Uint8List webBytes =
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

      if (webBytes.lengthInBytes > 150 * 1024 * 1024) {
        debugPrint(
          '[3D VIEW][WARN] (web) Model is '
              '${(webBytes.lengthInBytes / 1024 / 1024).toStringAsFixed(1)} MB. '
              'Consider a Draco / texture-optimized export for faster mobile loads.',
        );
      }

      _modelHttpUrl = url;

      debugPrint('[3D VIEW] (web) GLB verified: ${webBytes.length} bytes.');

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

  void setStateSafe(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  void _modelLoadedChanged() {
    if (!mounted) return;

    final loaded = _controller.onModelLoaded.value;

    debugPrint('[3D CONTROLLER] Loaded: $loaded');

    if (loaded == true) {
      _watchdogTimer?.cancel();
      setState(() {
        _progress = 1.0;
        _status = '3D model successfully loaded';
      });
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

      _modelHttpUrl = null;
      _preparedWebBytes = null;
      _isReady = false;

      newFuture = _prepareModel();
      _prepareFuture = newFuture;
    });

    _watchPreparedFuture(newFuture);
    _armWatchdog();
  }

  /// Opens the VR/AR experience (native: in-app stereo WebView page;
  /// web: new browser tab with an AR/VR-enabled `<model-viewer>`).
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

    Timer(const Duration(seconds: 30), () {
      html.Url.revokeObjectUrl(pageBlobUrl);
      html.Url.revokeObjectUrl(modelBlobUrl);
    });
  }

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
    _fullscreenSub?.cancel();

    // Leave browser fullscreen if the screen is closed while in it.
    if (_isFullscreen) {
      if (kIsWeb) {
        try {
          if (html.document.fullscreenElement != null) {
            html.document.exitFullscreen();
          }
        } catch (_) {}
      } else {
        unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
      }
    }

    _controller.onModelLoaded.removeListener(
      _modelLoadedChanged,
    );

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

    unawaited(_localServer.stop());

    _downloader?.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Back button / back gesture: leave fullscreen first, then the screen.
    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isFullscreen) {
          _exitFullscreen();
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
            // FULLSCREEN - enabled only after the model is loaded.
            IconButton(
              tooltip: 'Full screen',
              onPressed: _isReady ? _toggleFullscreen : null,
              icon: Icon(
                Icons.fullscreen,
                color: _isReady ? Colors.white : Colors.white24,
                size: 28,
              ),
            ),
            // AR/VR.
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
            // QR / shareable link.
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
        body: FutureBuilder<_PreparedModel>(
          future: _prepareFuture,
          builder: (context, snapshot) {
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

            return LayoutBuilder(
              builder: (context, constraints) {
                final deviceType = deviceTypeOf(constraints.maxWidth);

                // Bottom status bar strip (hidden in fullscreen).
                final double bottomSafeInset =
                    MediaQuery.of(context).padding.bottom;
                final double statusBarContentHeight =
                deviceType.isDesktop ? 48.0 : 44.0;
                const double statusBarVerticalPadding = 24.0;
                final double maskHeight = _isFullscreen
                    ? 0.0
                    : statusBarContentHeight +
                    statusBarVerticalPadding +
                    bottomSafeInset;

                // Fullscreen => no max-width stage, use the whole screen.
                final double stageMaxWidth =
                (deviceType.isDesktop && !_isFullscreen)
                    ? 1700.0
                    : double.infinity;

                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: stageMaxWidth),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // ---- 3D VIEWER (always child #0 so it is
                        // never rebuilt/reloaded when toggling
                        // fullscreen) --------------------------------
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
                            key: ValueKey(prepared.localUrl),
                            src: prepared.localUrl,
                            controller: _controller,
                            activeGestureInterceptor: true,
                            enableTouch: true,
                            progressBarColor: Colors.white,
                            onProgress: (double progressValue) {
                              if (!mounted) return;

                              setState(() {
                                _progress =
                                    progressValue.clamp(0.0, 1.0).toDouble();

                                _status = 'Rendering 3D model... '
                                    '${(_progress * 100).toStringAsFixed(0)}%';
                              });

                              _armWatchdog();
                            },
                            onLoad: (String modelAddress) {
                              debugPrint('[3D VIEW] onLoad: $modelAddress');

                              if (!mounted) return;

                              _watchdogTimer?.cancel();

                              setState(() {
                                _status = '3D model ready';
                              });
                            },
                            onError: (String error) {
                              debugPrint(
                                '[3D VIEW][ERROR] Renderer onError: $error',
                              );

                              if (!mounted) return;

                              setState(() {
                                _status = '3D renderer error - see debug '
                                    'console for details ($error)';
                              });
                            },
                          ),

                        // ---- Like button (top-right) ---------------
                        // PointerInterceptor => clicks reach the button
                        // instead of being swallowed by the iframe.
                        if (_votingEnabled)
                          Positioned(
                            top: 12,
                            right: 12,
                            child: SafeArea(
                              bottom: false,
                              child: PointerInterceptor(
                                child: _HeartLikeButton(
                                  count: _likeCount,
                                  active: _myVote == 'like',
                                  onPressed: () => _castVote('like'),
                                  scaleUp: deviceType.isDesktop,
                                ),
                              ),
                            ),
                          ),

                        // ---- CLOSE (X) button (top-left) -----------
                        // Only while fullscreen.
                        if (_isFullscreen)
                          Positioned(
                            top: 12,
                            left: 12,
                            child: SafeArea(
                              bottom: false,
                              child: PointerInterceptor(
                                child: _FullscreenCloseButton(
                                  onPressed: _exitFullscreen,
                                  scaleUp: deviceType.isDesktop,
                                ),
                              ),
                            ),
                          ),

                        // ---- Bottom status bar (hidden in
                        // fullscreen) ---------------------------------
                        if (!_isFullscreen)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: maskHeight,
                            child: PointerInterceptor(
                              child: Material(
                                color: const Color(0xFF0B0F14),
                                child: SafeArea(
                                  top: false,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal:
                                      deviceType.isDesktop ? 24 : 12,
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

  /// Web only: validated GLB bytes for the blob-URL based viewer and
  /// the AR/VR new-tab viewer.
  final Uint8List? webBytes;

  const _PreparedModel({
    required this.localUrl,
    required this.sizeBytes,
    this.webBytes,
  });
}

/// ===============================================================
/// WEB-ONLY GLB VIEWER (iframe + <model-viewer> + blob: URL)
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

  String? _modelBlobUrl;

  @override
  void initState() {
    super.initState();

    final modelBlob = html.Blob(<Object>[widget.bytes], 'model/gltf-binary');
    _modelBlobUrl = html.Url.createObjectUrlFromBlob(modelBlob);

    debugPrint(
      '[WEB VIEWER] Built blob URL for "${widget.modelName}": '
          '$_modelBlobUrl (${widget.bytes.lengthInBytes} bytes)',
    );

    _html = buildModelViewerHtml(
      modelSrc: _modelBlobUrl!,
      title: widget.modelName,
    );
  }

  void _handleBridgeMessage(String data) {
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

/// Low-level iframe host (platform view) pointed at a Blob URL.
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

    final blob = html.Blob(<Object>[widget.htmlContent], 'text/html');
    _blobUrl = html.Url.createObjectUrlFromBlob(blob);

    final iframe = html.IFrameElement()
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allowFullscreen = true
      ..allow = 'accelerometer; gyroscope; xr-spatial-tracking; fullscreen'
      ..src = _blobUrl;

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
          (int viewId) => iframe,
    );

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
/// IN-APP STEREO VR SCREEN (non-web platforms)
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
      ..setBackgroundColor(const Color(0xFF000000))
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
  Widget build(BuildContext context) {
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
/// UI HELPERS
/// ===============================================================

/// Round "X" button shown top-left while in fullscreen.
class _FullscreenCloseButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool scaleUp;

  const _FullscreenCloseButton({
    required this.onPressed,
    this.scaleUp = false,
  });

  @override
  Widget build(BuildContext context) {
    final double pad = scaleUp ? 12 : 10;
    final double iconSize = scaleUp ? 24 : 22;

    return Tooltip(
      message: 'Close full screen',
      child: Material(
        color: const Color(0xCC151C24),
        shape: const CircleBorder(
          side: BorderSide(color: Colors.white24),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          mouseCursor: SystemMouseCursors.click,
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.all(pad),
            child: Icon(
              Icons.close,
              color: Colors.white,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}

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
        _dotCount = (_dotCount + 1) % 6;
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
            padding: const EdgeInsets.symmetric(horizontal: 28),
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
  Widget build(BuildContext context) {
    final sizeMb = sizeBytes / 1024 / 1024;
    final sizeSuffix =
    sizeBytes > 0 ? '  •  ${sizeMb.toStringAsFixed(1)} MB' : '';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xDD111820),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Icon(
              Icons.check_circle,
              color: Colors.greenAccent,
              size: deviceType.isDesktop ? 21 : 19,
            ),
            const SizedBox(width: 8),
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

/// Heart-shaped Like button with a small "pop" bounce animation.
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
          mouseCursor: SystemMouseCursors.click,
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
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
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
              const SizedBox(height: 18),
              const Text(
                '3D model failed to load',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                error?.toString() ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Full details were also printed to the debug console.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}