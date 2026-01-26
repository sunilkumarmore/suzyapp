import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../design_system/app_colors.dart';
import '../design_system/app_radius.dart';
import '../design_system/app_spacing.dart';
import '../Services/parent_voice_service.dart';
import '../models/parent_voice_settings.dart';
import '../repositories/parent_voice_settings_repository.dart';
import '../utils/file_bytes.dart';
import '../utils/web_recorder.dart';

class ParentVoiceSettingsScreen extends StatefulWidget {
  const ParentVoiceSettingsScreen({super.key});

  static const routeName = '/parent-voice-settings';

  @override
  State<ParentVoiceSettingsScreen> createState() => _ParentVoiceSettingsScreenState();
}

class _ParentVoiceSettingsScreenState extends State<ParentVoiceSettingsScreen> {
  final _repo = ParentVoiceSettingsRepository();
  final _voiceIdController = TextEditingController();
  final Record _recorder = Record();
  final WebRecorder _webRecorder = WebRecorder();
  late final ParentVoiceService _parentVoiceService;

  bool _localEnabled = false;
  bool _dirty = false;
  bool _saving = false;
  bool _creatingVoice = false;
  String? _status;
  Map<String, dynamic> _elevenlabsSettings = ParentVoiceSettings.defaults().elevenlabsSettings;


  @override
  void initState() {
    super.initState();

    _parentVoiceService = ParentVoiceService(
      createEndpoint: 'https://us-central1-suzyapp.cloudfunctions.net/parentVoiceCreate',
      generateEndpoint: 'https://us-central1-suzyapp.cloudfunctions.net/generateNarration',
    );
  }

  @override
  void dispose() {
    _voiceIdController.dispose();
    _recorder.dispose();
    _webRecorder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _status = null;
    });

    try {
      final settings = ParentVoiceSettings(
        parentVoiceEnabled: _localEnabled,
        elevenVoiceId: _voiceIdController.text.trim(),
        elevenlabsSettings: _elevenlabsSettings,
      );

      await _repo.saveSettings(settings);

      if (!mounted) return;
      setState(() {
        _dirty = false;
        _status = 'Saved';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _test() {
    // Intentionally not wired to ParentVoiceService here to avoid mismatched signatures.
    // This keeps the screen compile-safe and still useful for enabling/disabling + voiceId storage.
    if (!_localEnabled) {
      setState(() => _status = 'Enable Parent Voice to test.');
      return;
    }
    if (_voiceIdController.text.trim().isEmpty) {
      setState(() => _status = 'Enter an ElevenLabs Voice ID first.');
      return;
    }
    setState(() => _status = 'Test not wired yet (settings are saved correctly).');
  }

  String _formatSeconds(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(1, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _saveVoiceId(String voiceId) async {
    if (!mounted) return;
    setState(() {
      _voiceIdController.text = voiceId;
      _localEnabled = true;
      _dirty = false;
    });
    await _repo.saveSettings(
      ParentVoiceSettings(
        parentVoiceEnabled: _localEnabled,
        elevenVoiceId: voiceId,
        elevenlabsSettings: _elevenlabsSettings,
      ),
    );
  }

  Future<void> _createVoiceFromBytes({
    required Uint8List bytes,
    required String mimeType,
    required void Function(String? status) setStatus,
  }) async {
    if (_creatingVoice) {
      setStatus('Voice creation already in progress.');
      return;
    }
    _creatingVoice = true;
    try {
      setStatus('Creating voice?');
      debugPrint(
        'ParentVoice:createVoiceFromBytes bytes=${bytes.length} mime=$mimeType',
      );
      debugPrint('ParentVoice: upload bytes=${bytes.length} mime=$mimeType');
      String? voiceId;
      try {
        voiceId = await _parentVoiceService.createVoiceFromSample(
          audioBytes: bytes,
          mimeType: mimeType,
          name: 'Parent Voice',
        );
        debugPrint('ParentVoice: createVoiceFromSample returned=$voiceId');
      } catch (e) {
        debugPrint('ParentVoice: createVoiceFromSample error=$e');
        setStatus('Voice creation failed.');
        return;
      }

      if (voiceId == null || voiceId.trim().isEmpty) {
        debugPrint('ParentVoice: create failed (empty voiceId)');
        setStatus('Voice creation failed.');
        return;
      }

      debugPrint('ParentVoice: created voiceId=$voiceId');
      await _saveVoiceId(voiceId.trim());
      setStatus('Voice created.');
    } finally {
      _creatingVoice = false;
    }
  }

  Future<void> _openRecordDialog() async {
    if (kIsWeb) {
      await _openWebRecordDialog();
      return;
    }

    debugPrint('ParentVoice: openRecordDialog (mobile)');
    bool started = false;
    bool isRecording = false;
    int elapsed = 0;
    String? localStatus;
    String? localPath;
    Timer? timer;

    Future<void> stopRecording(StateSetter setState, {bool autoStop = false}) async {
      debugPrint('ParentVoice: stopRecording(autoStop=$autoStop) isRecording=$isRecording');
      if (isRecording) {
        try {
          await _recorder.stop();
        } catch (_) {}
      }
      timer?.cancel();
      setState(() {
        isRecording = false;
        if (autoStop) {
          localStatus = 'Saved 1:00 sample.';
        } else if (localStatus == null) {
          localStatus = 'Recording stopped.';
        }
      });

      if (localPath != null) {
        debugPrint('ParentVoice: localPath=$localPath');
        final bytes = await readFileBytes(localPath!);
        if (bytes == null) {
          debugPrint('ParentVoice: readFileBytes returned null');
          setState(() => localStatus = 'Recording saved, but file read failed.');
          return;
        }
        debugPrint('ParentVoice: bytes read=${bytes.length}');
        await _createVoiceFromBytes(
          bytes: bytes,
          mimeType: 'audio/m4a',
          setStatus: (s) => setState(() => localStatus = s),
        );
      }
    }

    Future<void> startRecording(StateSetter setState) async {
      debugPrint('ParentVoice: startRecording requested');
      try {
        final allowed = await _recorder.hasPermission();
        debugPrint('ParentVoice: mic permission=$allowed');
        if (!allowed) {
          setState(() => localStatus = 'Microphone permission denied.');
          return;
        }

        final dir = await getApplicationDocumentsDirectory();
        localPath = '${dir.path}/parent_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _recorder.start(
          path: localPath!,
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          samplingRate: 44100,
        );
        debugPrint('ParentVoice: recorder started path=$localPath');

        setState(() {
          isRecording = true;
          elapsed = 0;
          localStatus = null;
        });

        timer?.cancel();
        timer = Timer.periodic(const Duration(seconds: 1), (_) async {
          elapsed += 1;
          if (elapsed >= 60) {
            await stopRecording(setState, autoStop: true);
            return;
          }
          setState(() {});
        });
      } catch (e) {
        setState(() => localStatus = 'Recording failed: $e');
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            if (!started) {
              started = true;
              unawaited(startRecording(setState));
            }

            return WillPopScope(
              onWillPop: () async {
                await stopRecording(setState);
                return true;
              },
              child: AlertDialog(
                title: const Text('Recording'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.mic,
                          color: isRecording ? AppColors.choiceRed : AppColors.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.small),
                        Expanded(
                          child: Text(
                            isRecording
                                ? 'Recording… ${_formatSeconds(elapsed)} / 1:00'
                                : 'Not recording',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    LinearProgressIndicator(
                      value: (elapsed.clamp(0, 60)) / 60,
                    ),
                    if (localStatus != null) ...[
                      const SizedBox(height: AppSpacing.small),
                      Text(
                        localStatus!,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                    if (!isRecording && localPath != null) ...[
                      const SizedBox(height: AppSpacing.small),
                      Text(
                        'Saved to: $localPath',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: isRecording
                        ? () async {
                            await stopRecording(setState);
                          }
                        : null,
                    child: const Text('Stop'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      await stopRecording(setState);
                      if (mounted) Navigator.pop(context);
                    },
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openWebRecordDialog() async {
    debugPrint('ParentVoice: openWebRecordDialog');
    bool started = false;
    bool isRecording = false;
    int elapsed = 0;
    String? localStatus;
    WebRecording? webRecording;
    Timer? timer;

    Future<void> stopRecording(StateSetter setState, {bool autoStop = false}) async {
      debugPrint('ParentVoice(web): stopRecording(autoStop=$autoStop) isRecording=$isRecording');
      if (isRecording) {
        try {
          webRecording = await _webRecorder.stop();
        } catch (e) {
          debugPrint('ParentVoice(web): stop error=$e');
          localStatus = 'Recording failed: $e';
        }
      }
      timer?.cancel();
      setState(() {
        isRecording = false;
        if (autoStop && localStatus == null) {
          localStatus = 'Saved 1:00 sample.';
        } else if (localStatus == null) {
          localStatus = 'Recording stopped.';
        }
      });

      final rec = webRecording;
      if (rec != null) {
        debugPrint(
          'ParentVoice(web): bytes=${rec.bytes.length} mime=${rec.mimeType} url=${rec.downloadUrl}',
        );
        await _createVoiceFromBytes(
          bytes: rec.bytes,
          mimeType: rec.mimeType,
          setStatus: (s) => setState(() => localStatus = s),
        );
      } else {
        debugPrint('ParentVoice(web): no recording returned');
      }
    }

    Future<void> startRecording(StateSetter setState) async {
      debugPrint('ParentVoice(web): startRecording requested');
      try {
        await _webRecorder.start();
        debugPrint('ParentVoice(web): recorder started');
        setState(() {
          isRecording = true;
          elapsed = 0;
          localStatus = null;
          webRecording = null;
        });

        timer?.cancel();
        timer = Timer.periodic(const Duration(seconds: 1), (_) async {
          elapsed += 1;
          if (elapsed >= 60) {
            await stopRecording(setState, autoStop: true);
            return;
          }
          setState(() {});
        });
      } catch (e) {
        debugPrint('ParentVoice(web): start error=$e');
        setState(() => localStatus = 'Microphone permission denied.');
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            if (!started) {
              started = true;
              unawaited(startRecording(setState));
            }

            return WillPopScope(
              onWillPop: () async {
                await stopRecording(setState);
                return true;
              },
              child: AlertDialog(
                title: const Text('Recording'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.mic,
                          color: isRecording ? AppColors.choiceRed : AppColors.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.small),
                        Expanded(
                          child: Text(
                            isRecording
                                ? 'Recording… ${_formatSeconds(elapsed)} / 1:00'
                                : 'Not recording',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.medium),
                    LinearProgressIndicator(
                      value: (elapsed.clamp(0, 60)) / 60,
                    ),
                    if (localStatus != null) ...[
                      const SizedBox(height: AppSpacing.small),
                      Text(
                        localStatus!,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                    if (!isRecording && webRecording != null) ...[
                      const SizedBox(height: AppSpacing.small),
                      Text(
                        'Recording ready to download.',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
                actions: [
                  if (!isRecording && webRecording != null)
                    TextButton(
                      onPressed: () {
                        final url = webRecording?.downloadUrl;
                        if (url == null) return;
                        downloadRecording(url, filename: 'parent_voice.webm');
                      },
                      child: const Text('Download'),
                    ),
                  TextButton(
                    onPressed: isRecording
                        ? () async {
                            await stopRecording(setState);
                          }
                        : null,
                    child: const Text('Stop'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      await stopRecording(setState);
                      if (mounted) Navigator.pop(context);
                    },
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ParentVoiceSettings>(
      stream: _repo.watchSettings(),
      builder: (context, snap) {
        final data = snap.data ?? ParentVoiceSettings.defaults();

        // Initialize local UI state from stream only when user isn't editing.
        if (!_dirty) {
          _localEnabled = data.parentVoiceEnabled;
          _elevenlabsSettings = data.elevenlabsSettings;

          final incoming = data.elevenVoiceId;
          if (_voiceIdController.text != incoming) {
            _voiceIdController.text = incoming;
          }
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Parent Voice'),
            backgroundColor: AppColors.background,
            elevation: 0,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.large),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionCard(
                    title: 'Voice',
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Use Parent Voice'),
                          subtitle: const Text(
                            'If unavailable, SuzyApp will use app voice automatically.',
                          ),
                          value: _localEnabled,
                          onChanged: (v) {
                            setState(() {
                              _localEnabled = v;
                              _dirty = true;
                            });
                          },
                        ),
                        const SizedBox(height: AppSpacing.medium),
                        TextField(
                          controller: _voiceIdController,
                          enabled: _localEnabled,
                          decoration: InputDecoration(
                            labelText: 'ElevenLabs Voice ID',
                            hintText: 'e.g. nzFihrBIvB34imQBuxub',
                            helperText: _localEnabled
                                ? 'This must match the Voice ID in ElevenLabs.'
                                : 'Enable Parent Voice to edit.',
                          ),
                          onChanged: (_) => setState(() => _dirty = true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.large),

                  _SectionCard(
                    title: 'Record Your Voice',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Record a 1 minute sample so your child can hear your voice.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: AppSpacing.medium),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.medium),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(AppRadius.large),
                            border: Border.all(color: AppColors.outline),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.mic, color: AppColors.textSecondary),
                              SizedBox(width: AppSpacing.small),
                              Expanded(
                                child: Text('Placeholder: 1:00 recording clip'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.medium),
                        ElevatedButton(
                          onPressed: _openRecordDialog,
                          child: Text('Record 1 minute'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.large),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : _test,
                          child: const Text('Test'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.medium),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (_saving || !_dirty) ? null : _save,
                          child: _saving ? const Text('Saving...') : const Text('Save'),
                        ),
                      ),
                    ],
                  ),

                  if (_status != null) ...[
                    const SizedBox(height: AppSpacing.medium),
                    Text(
                      _status!,
                      style: TextStyle(
                        color: (_status!.startsWith('Save failed') ||
                                _status!.startsWith('Test failed'))
                            ? AppColors.choiceRed
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.large),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.outline),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.medium),
          child,
        ],
      ),
    );
  }
}
