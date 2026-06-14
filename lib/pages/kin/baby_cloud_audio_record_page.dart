import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../widgets/toast_utils.dart';
import 'baby_cloud_entry_edit_page.dart';

class BabyCloudAudioRecordPage extends StatefulWidget {
  const BabyCloudAudioRecordPage({super.key});

  @override
  State<BabyCloudAudioRecordPage> createState() =>
      _BabyCloudAudioRecordPageState();
}

class _BabyCloudAudioRecordPageState extends State<BabyCloudAudioRecordPage> {
  final _recorder = AudioRecorder();
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  String? _path;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        centerTitle: true,
        leadingWidth: 82.w,
        leading: TextButton(
          onPressed: () => Get.back(result: false),
          child: const Text('取消'),
        ),
        title: const Text('录音'),
      ),
      body: Column(
        children: [
          SizedBox(height: 116.h),
          Text(
            _formatDuration(_elapsed),
            style: TextStyle(
              fontSize: 58.sp,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w300,
            ),
          ),
          SizedBox(height: 90.h),
          Expanded(
            child: CustomPaint(
              painter: _WavePainter(active: _recording),
              child: const SizedBox.expand(),
            ),
          ),
          SizedBox(height: 36.h),
          GestureDetector(
            onTap: _recording ? _stop : _start,
            child: Container(
              width: 104.w,
              height: 104.w,
              decoration: BoxDecoration(
                color: const Color(0xFFFFC22D),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFFF2C2), width: 10.w),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFC22D).withValues(alpha: 0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(
                _recording ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 44.sp,
              ),
            ),
          ),
          SizedBox(height: 14.h),
          Text(
            _recording ? '停止录音' : '开始录音',
            style: TextStyle(fontSize: 19.sp, color: Colors.grey.shade700),
          ),
          if (_path != null && !_recording) ...[
            SizedBox(height: 18.h),
            FilledButton(
              onPressed: _next,
              child: const Text('下一步'),
            ),
          ],
          SizedBox(height: 40.h),
        ],
      ),
    );
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      ToastUtils.showWarning('请允许麦克风权限后再录音');
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final folder =
        Directory('${dir.path}${Platform.pathSeparator}baby_cloud_records');
    await folder.create(recursive: true);
    final path =
        '${folder.path}${Platform.pathSeparator}record_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    setState(() {
      _path = path;
      _elapsed = Duration.zero;
      _recording = true;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(milliseconds: 200));
    });
  }

  Future<void> _stop() async {
    final path = await _recorder.stop();
    _timer?.cancel();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _path = path ?? _path;
    });
  }

  void _next() {
    final path = _path;
    if (path == null) return;
    Get.off(
      () => BabyCloudEntryEditPage(
        audioPath: path,
        audioFileName: path.split(Platform.pathSeparator).last,
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final centis = (duration.inMilliseconds.remainder(1000) ~/ 10)
        .toString()
        .padLeft(2, '0');
    return '$minutes:$seconds.$centis';
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter({required this.active});

  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFEFEFEF)
      ..strokeWidth = 1;
    final centerY = size.height * 0.5;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), paint);
    final accent = Paint()
      ..color = const Color(0xFFFF4D7D)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width / 2, centerY - 92),
      Offset(size.width / 2, centerY + 92),
      accent,
    );
    canvas.drawCircle(Offset(size.width / 2, centerY - 92), 5, accent);
    canvas.drawCircle(Offset(size.width / 2, centerY + 92), 5, accent);
    if (!active) return;
    final tick = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;
    for (var i = 0; i < 18; i++) {
      final x = size.width / 2 + i * 28;
      canvas.drawLine(Offset(x, centerY), Offset(x, centerY + 18), tick);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      oldDelegate.active != active;
}
