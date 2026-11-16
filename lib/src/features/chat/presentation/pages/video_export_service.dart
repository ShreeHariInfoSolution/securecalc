import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'video_preview_pane.dart';

class VideoExportService {
  static Future<File> export(File src, VideoEdit e) async {
    if (!e.isEdited) return src;
    try {
      final tmp = await getTemporaryDirectory();
      final out = '${tmp.path}/vid_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final args = <String>['-y'];
      if (e.trimmed) {
        args.addAll(['-ss', (e.start.inMilliseconds / 1000).toStringAsFixed(3)]);
      }
      args.addAll(['-i', src.path]);
      if (e.trimmed) {
        args.addAll(['-t', (e.length.inMilliseconds / 1000).toStringAsFixed(3)]);
      }
      if (e.trimmed) {
        // re-encode so the cut is frame-accurate
        args.addAll(['-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23']);
        args.addAll(e.muted ? ['-an'] : ['-c:a', 'aac']);
      } else {
        // mute only -> no re-encode, instant
        args.addAll(['-c:v', 'copy', '-an']);
      }
      args.addAll(['-movflags', '+faststart', out]);

      final session = await FFmpegKit.executeWithArguments(args);
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc) && File(out).existsSync()) return File(out);
    } catch (_) {}
    return src; // fall back to the original
  }
}
