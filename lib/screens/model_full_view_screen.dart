import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

/// Full-screen 3D / AR viewer for a single model.
/// Navigate here from ModelsScreen when the user taps a model card.
class ModelFullViewScreen extends StatelessWidget {
  final String modelName;
  final String modelUrl;

  const ModelFullViewScreen({
    super.key,
    required this.modelName,
    required this.modelUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white70),
        title: Text(
          modelName,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ModelViewer(
        src: modelUrl,
        alt: modelName,
        ar: true,
        arModes: const ['scene-viewer', 'webxr', 'quick-look'],
        autoRotate: true,
        cameraControls: true,
        disableZoom: false,
        backgroundColor: const Color(0xFF0D0D0D),
        loading: Loading.eager,
      ),
    );
  }
}