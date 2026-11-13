import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../settings.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _c;
  bool _torch = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final c = CameraController(back, ResolutionPreset.veryHigh, enableAudio: false);
      await c.initialize();
      if (appSettings.autoTorch) {
        await c.setFlashMode(FlashMode.torch);
        _torch = true;
      }
      if (mounted) setState(() => _c = c);
    } catch (e) {
      if (mounted) setState(() => _err = 'Kamera tidak dapat dibuka: $e');
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    final c = _c;
    if (c == null || c.value.isTakingPicture) return;
    final f = await c.takePicture();
    final Uint8List b = await f.readAsBytes();
    if (mounted) Navigator.pop(context, b);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Ambil Foto Rak'), actions: [
        IconButton(
          icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
          tooltip: 'Flash/Torch',
          onPressed: c == null
              ? null
              : () async {
                  _torch = !_torch;
                  await c.setFlashMode(_torch ? FlashMode.torch : FlashMode.off);
                  setState(() {});
                },
        ),
      ]),
      body: _err != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_err!, style: const TextStyle(color: Colors.white))))
          : c == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Expanded(child: Center(child: CameraPreview(c))),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FloatingActionButton.large(onPressed: _shoot, child: const Icon(Icons.camera_alt)),
                  ),
                ]),
    );
  }
}
