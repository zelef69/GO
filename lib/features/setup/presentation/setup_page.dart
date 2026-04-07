import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/update_service.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({required this.updateService, super.key});

  final UpdateService updateService;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> with WidgetsBindingObserver {
  static final Uri _lineContactUri = Uri.parse(
    'https://line.me/R/ti/p/%40615yysio',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.updateService.refreshManifestOnly());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.updateService.resumePendingInstallIfPossible());
      unawaited(widget.updateService.refreshManifestOnly());
    }
  }

  Future<void> _runUpdateFlow() async {
    await widget.updateService.startUpdateFlow();
    if (!mounted) {
      return;
    }
    final message = widget.updateService.errorMessage?.trim().isNotEmpty == true
        ? widget.updateService.errorMessage!
        : widget.updateService.message;
    if (message.trim().isEmpty) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _contactAdminViaLine() async {
    final launched = await launchUrl(
      _lineContactUri,
      mode: LaunchMode.externalApplication,
    );
    if (launched || !mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('ไม่สามารถเปิด LINE ได้')));
  }

  String _primaryActionLabel(UpdateService updateService) {
    if (updateService.awaitingInstallPermission) {
      return 'อนุญาตการติดตั้ง';
    }
    switch (updateService.state) {
      case UpdateFlowState.checking:
        return 'กำลังตรวจสอบ...';
      case UpdateFlowState.downloading:
        final progress = (updateService.downloadProgress * 100).toStringAsFixed(
          0,
        );
        return 'กำลังดาวน์โหลด $progress%';
      case UpdateFlowState.downloaded:
      case UpdateFlowState.readyToInstall:
      case UpdateFlowState.installing:
        return 'ติดตั้ง GO_PLAY';
      case UpdateFlowState.verifying:
        return 'กำลังตรวจสอบไฟล์...';
      case UpdateFlowState.updateAvailable:
        return 'อัปเดต GO_PLAY';
      case UpdateFlowState.noUpdate:
        return 'ตรวจสอบอีกครั้ง';
      case UpdateFlowState.error:
        return 'ลองอีกครั้ง';
    }
  }

  String _formatPublishedAt(DateTime publishedAt) {
    if (publishedAt.millisecondsSinceEpoch <= 0) {
      return '-';
    }
    final local = publishedAt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F6F2),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.updateService,
          builder: (context, _) {
            final updateService = widget.updateService;
            final latestManifest = updateService.manifest;
            final currentVersionText = updateService.currentVersionCode > 0
                ? '${updateService.currentVersionName} (${updateService.currentVersionCode})'
                : updateService.currentVersionName;
            final latestVersionText = latestManifest == null
                ? 'ยังไม่พบข้อมูล'
                : '${latestManifest.latestVersionName} (${latestManifest.latestVersionCode})';
            final publishedText = latestManifest == null
                ? '-'
                : _formatPublishedAt(latestManifest.publishedAt);
            final updateMessage = updateService.message.trim().isEmpty
                ? 'พร้อมสำหรับติดตั้งหรืออัปเดต GO_PLAY'
                : updateService.message.trim();
            final changelog = latestManifest?.changelog ?? const <String>[];

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              children: <Widget>[
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: const Color(0xFFE7E2DA)),
                    ),
                    child: Image.asset(
                      'assets/pic/logo-v2.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'GO_PLAY Setup',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 22),
                _SetupCard(
                  title: 'สถานะแอป',
                  child: Column(
                    children: <Widget>[
                      _InfoRow(
                        label: 'เวอร์ชันในเครื่อง',
                        value: currentVersionText,
                      ),
                      const SizedBox(height: 10),
                      _InfoRow(
                        label: 'เวอร์ชันล่าสุด',
                        value: latestVersionText,
                        highlight:
                            latestManifest != null &&
                            latestManifest.latestVersionCode >
                                updateService.currentVersionCode,
                      ),
                      const SizedBox(height: 10),
                      _InfoRow(label: 'เผยแพร่เมื่อ', value: publishedText),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _SetupCard(
                  title: 'สถานะล่าสุด',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        updateMessage,
                        style: TextStyle(
                          color: updateService.state == UpdateFlowState.error
                              ? Colors.red.shade700
                              : Colors.black87,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                      if (updateService.state ==
                          UpdateFlowState.downloading) ...[
                        const SizedBox(height: 14),
                        LinearProgressIndicator(
                          value: updateService.downloadProgress > 0
                              ? updateService.downloadProgress
                              : null,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ],
                    ],
                  ),
                ),
                if (changelog.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _SetupCard(
                    title: 'รายละเอียดเวอร์ชันล่าสุด',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (final item in changelog) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: Color(0xFFE62117),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item,
                                  style: const TextStyle(height: 1.45),
                                ),
                              ),
                            ],
                          ),
                          if (item != changelog.last)
                            const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: updateService.isBusy ? null : _runUpdateFlow,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE62117),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    _primaryActionLabel(updateService),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: updateService.isBusy
                      ? null
                      : () => updateService.refreshManifestOnly(),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('รีเฟรชสถานะ'),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _contactAdminViaLine,
                  icon: const Icon(Icons.support_agent_outlined),
                  label: const Text('ติดต่อแอดมิน'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7E2DA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(color: Colors.black.withOpacity(0.58)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: highlight ? const Color(0xFFE62117) : Colors.black87,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
