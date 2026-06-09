import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../bloc/attendance/attendance_bloc.dart';
import '../../themes/app_theme.dart';
import '../../config/app_config.dart';
import '../../widgets/common/loading_overlay.dart';

enum _ClockMode { clockIn, clockOut }

class CameraAttendanceScreen extends StatefulWidget {
  const CameraAttendanceScreen({super.key});
  @override
  State<CameraAttendanceScreen> createState() => _CameraAttendanceScreenState();
}

class _CameraAttendanceScreenState extends State<CameraAttendanceScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isCapturing = false;
  bool _isCollectingLiveness = false;
  _ClockMode _mode = _ClockMode.clockIn;

  // Liveness detection state
  final List<String> _livenessFrames = [];
  Timer? _livenessTimer;
  int _livenessProgress = 0;

  // Result state
  bool _showResult = false;
  bool _resultSuccess = false;
  String _resultMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _livenessTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _cameraController!.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      // Prefer front camera
      final frontCam = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        frontCam,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  /// Collect liveness frames (blink detection)
  Future<void> _collectLivenessFrames() async {
    setState(() {
      _isCollectingLiveness = true;
      _livenessFrames.clear();
      _livenessProgress = 0;
    });

    final completer = Completer<void>();
    int frameCount = 0;

    _livenessTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!mounted || _cameraController == null) {
        timer.cancel();
        completer.complete();
        return;
      }

      try {
        final image = await _cameraController!.takePicture();
        final bytes = await image.readAsBytes();
        _livenessFrames.add(base64Encode(bytes));
        frameCount++;

        if (mounted) {
          setState(() => _livenessProgress = frameCount);
        }

        if (frameCount >= AppConfig.livenessFrameCount) {
          timer.cancel();
          completer.complete();
        }
      } catch (_) {}
    });

    await completer.future;
    setState(() => _isCollectingLiveness = false);
  }

  /// Main capture + clock-in/out flow
  Future<void> _capture() async {
    if (_isCapturing || !_isInitialized || _cameraController == null) return;
    setState(() => _isCapturing = true);

    try {
      // Step 1: Collect liveness frames
      await _collectLivenessFrames();

      // Step 2: Capture final frame
      final image = await _cameraController!.takePicture();
      final bytes = await image.readAsBytes();
      final b64 = base64Encode(bytes);

      // Step 3: Dispatch BLoC event
      if (_mode == _ClockMode.clockIn) {
        context.read<AttendanceBloc>().add(
          AttendanceClockInFace(b64, livenessFrames: _livenessFrames),
        );
      } else {
        context.read<AttendanceBloc>().add(AttendanceClockOutFace(b64));
      }
    } catch (e) {
      _showError('Capture failed: $e');
    } finally {
      setState(() => _isCapturing = false);
    }
  }

  void _showError(String msg) {
    setState(() {
      _showResult = true;
      _resultSuccess = false;
      _resultMessage = msg;
    });
  }

  void _resetState() {
    setState(() {
      _showResult = false;
      _livenessFrames.clear();
      _livenessProgress = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AttendanceBloc, AttendanceState>(
      listener: (context, state) {
        if (state is AttendanceClockSuccess) {
          setState(() {
            _showResult = true;
            _resultSuccess = true;
            _resultMessage = state.message;
          });
        } else if (state is AttendanceClockError) {
          setState(() {
            _showResult = true;
            _resultSuccess = false;
            _resultMessage = state.message;
          });
        }
      },
      child: BlocBuilder<AttendanceBloc, AttendanceState>(
        builder: (context, state) {
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: const Text('Face Attendance'),
              actions: [
                // Mode toggle
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: SegmentedButton<_ClockMode>(
                    style: SegmentedButton.styleFrom(
                      backgroundColor: Colors.grey[900],
                      selectedBackgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                    ),
                    segments: const [
                      ButtonSegment(value: _ClockMode.clockIn,  label: Text('In',  style: TextStyle(fontSize: 12))),
                      ButtonSegment(value: _ClockMode.clockOut, label: Text('Out', style: TextStyle(fontSize: 12))),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() {
                      _mode = s.first;
                      _resetState();
                    }),
                  ),
                ),
              ],
            ),
            body: LoadingOverlay(
              isLoading: state is AttendanceLoading,
              child: _showResult
                  ? _ResultView(
                      success: _resultSuccess,
                      message: _resultMessage,
                      onDone: () {
                        _resetState();
                        Navigator.of(context).pop();
                      },
                      onRetry: _resetState,
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        // ── Camera Preview ──────────────────────
                        if (_isInitialized && _cameraController != null)
                          CameraPreview(_cameraController!)
                        else
                          const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),

                        // ── Face guide oval ─────────────────────
                        CustomPaint(painter: _FaceGuidePainter()),

                        // ── Liveness progress ───────────────────
                        if (_isCollectingLiveness)
                          Positioned(
                            top: 80,
                            left: 0, right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Text(
                                    'Please blink naturally…',
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                  ),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: _livenessProgress / AppConfig.livenessFrameCount,
                                    backgroundColor: Colors.white24,
                                    color: AppTheme.accentGreen,
                                  ),
                                ]),
                              ),
                            ),
                          ),

                        // ── Instructions ────────────────────────
                        Positioned(
                          bottom: 120,
                          left: 0, right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Text(
                                _mode == _ClockMode.clockIn
                                    ? 'Position face in oval, then tap to Clock In'
                                    : 'Position face in oval, then tap to Clock Out',
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),

                        // ── Capture Button ──────────────────────
                        Positioned(
                          bottom: 36,
                          left: 0, right: 0,
                          child: Center(
                            child: GestureDetector(
                              onTap: _isCapturing ? null : _capture,
                              child: Container(
                                width: 72, height: 72,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 4),
                                  color: _isCapturing
                                      ? Colors.grey
                                      : (_mode == _ClockMode.clockIn
                                          ? AppTheme.accentGreen
                                          : AppTheme.accentOrange),
                                ),
                                child: Icon(
                                  _isCapturing
                                      ? Icons.hourglass_bottom
                                      : (_mode == _ClockMode.clockIn
                                          ? Icons.login
                                          : Icons.logout),
                                  color: Colors.white,
                                  size: 32,
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
      ),
    );
  }
}

// ── Face Guide Oval Painter ────────────────────────────────────

class _FaceGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.38),
      width: size.width * 0.62,
      height: size.height * 0.40,
    );

    // Darken outside oval
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, Paint()..color = Colors.black45);
    canvas.drawOval(ovalRect, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Result View ───────────────────────────────────────────────

class _ResultView extends StatelessWidget {
  final bool success;
  final String message;
  final VoidCallback onDone;
  final VoidCallback onRetry;

  const _ResultView({
    required this.success,
    required this.message,
    required this.onDone,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Icon ──────────────────────────────────────────
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (success ? AppTheme.accentGreen : AppTheme.accentRed).withOpacity(0.1),
              ),
              child: Icon(
                success ? Icons.check_circle : Icons.error_outline,
                size: 60,
                color: success ? AppTheme.accentGreen : AppTheme.accentRed,
              ),
            ),
            const SizedBox(height: 24),

            Text(
              success ? 'Success!' : 'Recognition Failed',
              style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(fontSize: 15, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),

            // ── Actions ───────────────────────────────────────
            if (success)
              ElevatedButton.icon(
                onPressed: onDone,
                icon: const Icon(Icons.check),
                label: const Text('Done'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentGreen,
                  minimumSize: const Size(200, 52),
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: onDone,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try Again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
