import 'dart:async';
import 'dart:io';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import 'design.dart';
import 'editor.dart';
import 'photography.dart';

Future<Uint8List?> openFilmCamera(
  BuildContext context, {
  bool forAlbum = false,
}) => Navigator.of(context, rootNavigator: true).push<Uint8List>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _FilmCamera(forAlbum: forAlbum),
  ),
);

class _FilmCamera extends StatefulWidget {
  const _FilmCamera({required this.forAlbum});
  final bool forAlbum;

  @override
  State<_FilmCamera> createState() => _FilmCameraState();
}

enum _Adjustment { strength, zoom, exposure }

class _FilmCameraState extends State<_FilmCamera> with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraDescription? _selected;
  CameraController? _controller;
  Future<void> _releasePending = Future.value();
  String? _error;
  bool _opening = false;
  bool _busy = false;
  bool _asleep = false;
  bool _grid = true;
  bool _adjustingZoom = false;
  int _initGeneration = 0;
  double _minZoom = 1, _maxZoom = 1, _zoom = 1;
  double _pinchStart = 1;
  double _minEv = 0, _maxEv = 0, _ev = 0;
  Offset? _target;
  Timer? _focusTimer;
  FilmLook _look = FilmLook.bronze;
  FlashMode _flash = FlashMode.off;
  _Adjustment _adjustment = _Adjustment.strength;
  double _strength = .8;
  Uint8List? _shot;
  bool _unprocessedFallback = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusTimer?.cancel();
    _release();
    super.dispose();
  }

  Future<void> _release() {
    _initGeneration++;
    final current = _controller;
    _controller = null;
    if (current != null) {
      _releasePending = _releasePending
          .then((_) => current.dispose())
          .catchError((Object _) {});
    }
    return _releasePending;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _asleep = false;
      if (_shot == null && !_busy && _controller == null) _open();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _asleep = true;
      if (_controller != null) {
        setState(() {
          _release();
        });
      }
    }
  }

  Future<CameraController> _initialize(
    CameraDescription camera,
    ResolutionPreset preset,
  ) async {
    final controller = CameraController(camera, preset, enableAudio: false);
    try {
      await controller.initialize();
      return controller;
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
  }

  Future<void> _open([CameraDescription? selection]) async {
    if (_opening || _asleep || !mounted) return;
    setState(() {
      _opening = true;
      _error = null;
      _target = null;
    });
    await _release();
    final generation = _initGeneration;
    CameraController? next;
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw const FormatException('No camera');
      final selected =
          selection ??
          _selected ??
          _cameras
              .where((item) => item.lensDirection == CameraLensDirection.back)
              .firstOrNull ??
          _cameras.first;
      try {
        next = await _initialize(selected, ResolutionPreset.max);
      } on CameraException catch (error) {
        if (error.code.toLowerCase().contains('access')) rethrow;
        next = await _initialize(selected, ResolutionPreset.high);
      }
      var minZoom = 1.0, maxZoom = 1.0, minEv = 0.0, maxEv = 0.0;
      try {
        await next.setJpegImageQuality(98);
      } on CameraException {
        /* Keep camera default. */
      }
      try {
        minZoom = await next.getMinZoomLevel();
        maxZoom = await next.getMaxZoomLevel();
      } on CameraException {
        /* Fixed zoom camera. */
      }
      try {
        minEv = await next.getMinExposureOffset();
        maxEv = await next.getMaxExposureOffset();
      } on CameraException {
        /* Fixed exposure camera. */
      }
      if (!mounted || _asleep || generation != _initGeneration) return;
      setState(() {
        _selected = selected;
        _controller = next;
        _minZoom = minZoom;
        _maxZoom = maxZoom;
        _zoom = 1.0.clamp(minZoom, maxZoom);
        _minEv = minEv;
        _maxEv = maxEv;
        _ev = 0.0.clamp(minEv, maxEv);
        _flash = FlashMode.off;
      });
      next = null;
    } on CameraException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.code.toLowerCase().contains('access')
              ? 'Разреши доступ к камере в настройках Android.'
              : 'Не удалось открыть камеру.',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Камера недоступна.');
    } finally {
      await next?.dispose();
      if (mounted) setState(() => _opening = false);
    }
  }

  CameraDescription? get _otherLens {
    final direction = _selected?.lensDirection;
    return _cameras
        .where(
          (item) =>
              item.lensDirection != direction &&
              item.lensDirection != CameraLensDirection.external,
        )
        .firstOrNull;
  }

  Future<void> _cycleFlash() async {
    final camera = _controller;
    if (camera == null || _busy) return;
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    try {
      await camera.setFlashMode(next);
      if (mounted && camera == _controller) setState(() => _flash = next);
    } on CameraException {
      if (mounted) notify(context, 'Вспышка недоступна на этой камере');
    }
  }

  Future<void> _focus(TapUpDetails event, Size size) async {
    final camera = _controller;
    if (camera == null || _busy) return;
    final point = event.localPosition;
    final normalized = Offset(
      (point.dx / size.width).clamp(0, 1),
      (point.dy / size.height).clamp(0, 1),
    );
    setState(() => _target = point);
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted) setState(() => _target = null);
    });
    try {
      await camera.setFocusPoint(normalized);
    } on CameraException {
      /* Autofocus remains active. */
    }
    if (camera != _controller) return;
    try {
      await camera.setExposurePoint(normalized);
    } on CameraException {
      /* Autoexposure remains active. */
    }
  }

  void _setZoom(double value) {
    setState(() => _zoom = value.clamp(_minZoom, _maxZoom));
    final camera = _controller;
    if (_adjustingZoom || camera == null) return;
    _adjustingZoom = true;
    unawaited(() async {
      try {
        double sent;
        do {
          sent = _zoom;
          await camera.setZoomLevel(sent);
        } while (mounted && camera == _controller && _zoom != sent);
      } on CameraException {
        if (mounted && camera == _controller) {
          setState(() => _zoom = 1.0.clamp(_minZoom, _maxZoom));
        }
      } finally {
        _adjustingZoom = false;
      }
    }());
  }

  Future<void> _takePhoto() async {
    final camera = _controller;
    if (camera == null || _busy || _opening) return;
    final look = _look;
    final strength = _strength;
    setState(() => _busy = true);
    File? raw;
    try {
      final capture = await camera.takePicture();
      raw = File(capture.path);
      HapticFeedback.mediumImpact();
      await _release();
      final Uint8List bytes;
      try {
        bytes = await developPhoto(raw, look, strength);
        _unprocessedFallback = false;
      } catch (_) {
        final original = await raw.readAsBytes();
        _unprocessedFallback = true;
        if (mounted) setState(() => _shot = original);
        return;
      }
      if (mounted) setState(() => _shot = bytes);
    } catch (_) {
      if (mounted) notify(context, 'Не удалось сделать снимок');
    } finally {
      if (raw != null) await removeTemporaryPhoto(raw);
      if (mounted) {
        setState(() => _busy = false);
        if (_shot == null && _controller == null) unawaited(_open());
      }
    }
  }

  Future<void> _usePhoto(Uint8List photo) async {
    if (widget.forAlbum) {
      Navigator.of(context).pop(photo);
      return;
    }
    setState(() => _busy = true);
    try {
      if (await saveCameraPhoto(photo) && mounted) {
        notify(context, 'Снимок сохранён');
      }
    } catch (_) {
      if (mounted) notify(context, 'Не удалось сохранить снимок');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _viewfinder(CameraController camera) =>
      ValueListenableBuilder<CameraValue>(
        valueListenable: camera,
        builder: (context, value, child) {
          final landscape =
              value.deviceOrientation == DeviceOrientation.landscapeLeft ||
              value.deviceOrientation == DeviceOrientation.landscapeRight;
          final ratio = landscape ? value.aspectRatio : 1 / value.aspectRatio;
          return LayoutBuilder(
            builder: (context, limits) {
              final width = (limits.maxHeight * ratio).clamp(
                0.0,
                limits.maxWidth,
              );
              final size = Size(width, width / ratio);
              return Center(
                child: SizedBox.fromSize(
                  size: size,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: GestureDetector(
                      onTapUp: (event) => _focus(event, size),
                      onScaleStart: (_) => _pinchStart = _zoom,
                      onScaleUpdate: (event) {
                        if (event.pointerCount > 1 && _maxZoom > _minZoom) {
                          _setZoom(_pinchStart * event.scale);
                        }
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColorFiltered(
                            colorFilter: ColorFilter.matrix(
                              _look.preview(_strength),
                            ),
                            child: CameraPreview(camera),
                          ),
                          if (_grid)
                            const IgnorePointer(
                              child: CustomPaint(painter: _ViewfinderGrid()),
                            ),
                          if (_target case final point?)
                            Positioned(
                              left: point.dx - 23,
                              top: point.dy - 23,
                              child: IgnorePointer(
                                child: Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: bronze),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final shot = _shot;
    final camera = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(shot == null ? 'Камера TEMPUS' : 'Снимок'),
        actions: shot != null
            ? null
            : [
                IconButton(
                  tooltip:
                      'Вспышка: ${switch (_flash) {
                        FlashMode.auto => 'авто',
                        FlashMode.always => 'включена',
                        _ => 'выключена',
                      }}',
                  onPressed: camera == null || _busy ? null : _cycleFlash,
                  icon: Icon(switch (_flash) {
                    FlashMode.auto => Icons.flash_auto,
                    FlashMode.always => Icons.flash_on,
                    _ => Icons.flash_off,
                  }),
                ),
                IconButton(
                  tooltip: _grid ? 'Убрать сетку' : 'Показать сетку',
                  onPressed: () => setState(() => _grid = !_grid),
                  icon: Icon(_grid ? Icons.grid_on : Icons.grid_off),
                ),
              ],
      ),
      body: SafeArea(
        top: false,
        child: shot != null
            ? _review(shot)
            : Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      child: switch ((camera, _busy, _error)) {
                        (_, true, _) => const _CameraWait(
                          'Обрабатываю снимок…',
                        ),
                        (final CameraController active, _, _) => _viewfinder(
                          active,
                        ),
                        (_, _, final String error) => Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(18),
                                child: Text(error, textAlign: TextAlign.center),
                              ),
                              TextButton(
                                onPressed: _opening ? null : _open,
                                child: const Text('Повторить'),
                              ),
                            ],
                          ),
                        ),
                        _ => const _CameraWait('Открываю камеру…'),
                      },
                    ),
                  ),
                  if (camera != null && !_busy) ...[
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        spacing: 7,
                        children: [
                          for (final look in FilmLook.values)
                            ChoiceChip(
                              label: Text(look.label),
                              selected: look == _look,
                              onSelected: (_) => setState(() => _look = look),
                            ),
                        ],
                      ),
                    ),
                    _controls(),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        SizedBox(
                          width: 48,
                          child: camera != null && !_busy
                              ? IconButton(
                                  tooltip: 'Сбросить приближение',
                                  onPressed: _maxZoom > _minZoom
                                      ? () => _setZoom(1)
                                      : null,
                                  icon: Text('${_zoom.toStringAsFixed(1)}×'),
                                )
                              : null,
                        ),
                        Semantics(
                          button: true,
                          label: 'Сделать снимок',
                          child: InkResponse(
                            onTap: camera == null || _busy || _opening
                                ? null
                                : _takePhoto,
                            radius: 39,
                            child: Container(
                              width: 66,
                              height: 66,
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: camera == null || _busy
                                      ? border
                                      : bronze,
                                  width: 2,
                                ),
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: camera == null || _busy
                                      ? panel
                                      : bronze,
                                ),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Переключить фронтальную и основную камеры',
                          icon: const Icon(Icons.cameraswitch_outlined),
                          onPressed:
                              camera == null || _busy || _otherLens == null
                              ? null
                              : () => _open(_otherLens),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _controls() {
    final modes = [
      _Adjustment.strength,
      if (_maxZoom > _minZoom) _Adjustment.zoom,
      if (_maxEv > _minEv) _Adjustment.exposure,
    ];
    final mode = modes.contains(_adjustment)
        ? _adjustment
        : _Adjustment.strength;
    final (low, high, value) = switch (mode) {
      _Adjustment.strength => (0.0, 1.0, _strength),
      _Adjustment.zoom => (_minZoom, _maxZoom, _zoom),
      _Adjustment.exposure => (_minEv, _maxEv, _ev),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          PopupMenuButton<_Adjustment>(
            tooltip: 'Настройки съёмки',
            initialValue: mode,
            icon: const Icon(Icons.tune_rounded, color: bronze),
            onSelected: (value) => setState(() => _adjustment = value),
            itemBuilder: (_) => [
              for (final option in modes)
                PopupMenuItem(
                  value: option,
                  child: Text(switch (option) {
                    _Adjustment.strength => 'Сила эффекта',
                    _Adjustment.zoom => 'Приближение',
                    _Adjustment.exposure => 'Экспозиция',
                  }),
                ),
            ],
          ),
          Expanded(
            child: Slider(
              min: low,
              max: high,
              value: value.clamp(low, high),
              onChanged: switch (mode) {
                _Adjustment.strength =>
                  _look == FilmLook.original
                      ? null
                      : (v) => setState(() => _strength = v),
                _Adjustment.zoom => _setZoom,
                _Adjustment.exposure => (v) => setState(() => _ev = v),
              },
              onChangeEnd: mode == _Adjustment.exposure
                  ? (requested) async {
                      final camera = _controller;
                      if (camera == null) return;
                      try {
                        final applied = await camera.setExposureOffset(
                          requested,
                        );
                        if (mounted && camera == _controller) {
                          setState(() => _ev = applied);
                        }
                      } on CameraException {
                        if (mounted) {
                          notify(context, 'Настройка экспозиции недоступна');
                        }
                      }
                    }
                  : null,
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              switch (mode) {
                _Adjustment.strength =>
                  _look == FilmLook.original
                      ? '0%'
                      : '${(_strength * 100).round()}%',
                _Adjustment.zoom => '${_zoom.toStringAsFixed(1)}×',
                _Adjustment.exposure => '${_ev.toStringAsFixed(1)} EV',
              },
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _review(Uint8List photo) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: Column(
      children: [
        Expanded(
          child: InteractiveViewer(
            maxScale: 4,
            child: Center(
              child: Image.memory(photo, fit: BoxFit.contain, cacheWidth: 2400),
            ),
          ),
        ),
        if (jpegDimensions(photo) case (final width, final height))
          Text(
            '$width × $height',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        if (_unprocessedFallback)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Эффект не применился. Можно сохранить оригинал.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () {
                      setState(() => _shot = null);
                      _open();
                    },
              child: const Text('Переснять'),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : () => _usePhoto(photo),
              icon: const Icon(Icons.check),
              label: Text(widget.forAlbum ? 'В альбом' : 'В галерею'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _CameraWait extends StatelessWidget {
  const _CameraWait(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(label),
      ],
    ),
  );
}

class _ViewfinderGrid extends CustomPainter {
  const _ViewfinderGrid();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x66e7c48b)
      ..strokeWidth = .7;
    for (final fraction in [1 / 3, 2 / 3]) {
      canvas.drawLine(
        Offset(fraction * size.width, 0),
        Offset(fraction * size.width, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(0, fraction * size.height),
        Offset(size.width, fraction * size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ViewfinderGrid oldDelegate) => false;
}
