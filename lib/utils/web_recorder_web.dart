import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

class WebRecording {
  final Uint8List bytes;
  final String mimeType;
  final String downloadUrl;

  WebRecording({
    required this.bytes,
    required this.mimeType,
    required this.downloadUrl,
  });
}

class WebRecorder {
  html.MediaRecorder? _recorder;
  html.MediaStream? _stream;
  final List<html.Blob> _chunks = [];
  html.Blob? _lastBlob;

  Future<void> start() async {
    final mediaDevices = html.window.navigator.mediaDevices;
    if (mediaDevices == null) {
      throw StateError('MediaDevices not available.');
    }

    _stream = await mediaDevices.getUserMedia({'audio': true});
    _chunks.clear();
    _lastBlob = null;

    final recorder = html.MediaRecorder(_stream!);
    _recorder = recorder;

    recorder.addEventListener('dataavailable', (event) {
      final e = event as html.BlobEvent;
      if (e.data != null) {
        _lastBlob = e.data;
        _chunks.add(e.data!);
      }
    });

    recorder.addEventListener('error', (event) {
      final e = event as html.Event;
      html.window.console.error('MediaRecorder error: $e');
    });

    html.window.console.log('MediaRecorder mimeType=${recorder.mimeType}');

    // Timeslice ensures dataavailable fires while recording.
    recorder.start(1000);
  }

  Future<WebRecording?> stop() async {
    final recorder = _recorder;
    if (recorder == null) return null;

    final completer = Completer<WebRecording?>();
    void onStop(html.Event _) async {
      recorder.removeEventListener('stop', onStop);

      final blob = _chunks.isNotEmpty
          ? html.Blob(_chunks, 'audio/webm')
          : (_lastBlob ?? html.Blob([], 'audio/webm'));
      html.window.console
          .log('MediaRecorder stop: chunks=${_chunks.length}, blob=${blob.size}, type=${blob.type}');
      final url = html.Url.createObjectUrl(blob);

      _chunks.clear();
      _recorder = null;

      final stream = _stream;
      _stream = null;
      if (stream != null) {
        for (final track in stream.getTracks()) {
          track.stop();
        }
      }

      try {
        final reader = html.FileReader();
        reader.onError.first.then((_) {
          html.window.console.log('MediaRecorder: FileReader error=${reader.error}');
        });
        reader.readAsArrayBuffer(blob);
        await reader.onLoadEnd.first;
        if (reader.error != null) {
          html.window.console.log('MediaRecorder: FileReader error=${reader.error}');
          completer.complete(null);
          return;
        }
        if (reader.result == null) {
          html.window.console.log('MediaRecorder: FileReader result null');
          completer.complete(null);
          return;
        }
        final result = reader.result;
        if (result is ByteBuffer) {
          final bytes = Uint8List.view(result);
          html.window.console.log('MediaRecorder: bytes=${bytes.length}');
          completer.complete(
            WebRecording(bytes: bytes, mimeType: 'audio/webm', downloadUrl: url),
          );
        } else if (result is Uint8List) {
          html.window.console.log('MediaRecorder: bytes=${result.length}');
          completer.complete(
            WebRecording(bytes: result, mimeType: 'audio/webm', downloadUrl: url),
          );
        } else {
          html.window.console.log('MediaRecorder: unexpected result=${result.runtimeType}');
          completer.complete(null);
        }
      } catch (e) {
        html.window.console.log('MediaRecorder: FileReader exception=$e');
        completer.complete(null);
      }
    }

    recorder.addEventListener('stop', onStop);
    // Request a final chunk before stopping.
    recorder.requestData();
    recorder.stop();

    return completer.future;
  }

  void dispose() {
    final stream = _stream;
    _stream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        track.stop();
      }
    }
    _recorder = null;
    _chunks.clear();
  }
}

void downloadRecording(String url, {String filename = 'recording.webm'}) {
  final anchor = html.AnchorElement(href: url)
    ..download = filename
    ..click();
}
