import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes/app_routes.dart';
import '../../../services/update_service.dart';
import '../../auth/auth_controller.dart';
import '../../auth/domain/session_package_status.dart';
import '../account_placeholders.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({
    required this.authController,
    required this.updateService,
    super.key,
  });

  final AuthController authController;
  final UpdateService updateService;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> with WidgetsBindingObserver {
  static final Uri _lineContactUri = Uri.parse(
    'https://line.me/R/ti/p/%40615yysio',
  );

  bool _isSigningOut = false;
  Timer? _countdownTicker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _countdownTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
    unawaited(widget.updateService.refreshManifestOnly());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTicker?.cancel();
    _countdownTicker = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.updateService.resumePendingInstallIfPossible());
    }
  }

  void _showPlaceholderMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).pushNamed(AppRoutes.settings);
  }

  Future<void> _signOut() async {
    if (_isSigningOut) {
      return;
    }
    setState(() {
      _isSigningOut = true;
    });
    try {
      await widget.authController.signOut();
      if (!mounted) {
        return;
      }
      Navigator.of(context).popUntil((route) => route.isFirst);
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
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
      ..showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเปิดแอป LINE ได้')),
      );
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

  String _customerLevelLabel(String? plan) {
    final normalized = (plan ?? '').trim().toLowerCase();
    if (normalized.contains('3') || normalized.contains('level3')) {
      return 'ระดับ 3';
    }
    if (normalized.contains('2') || normalized.contains('level2')) {
      return 'ระดับ 2';
    }
    return 'ระดับ 1';
  }

  String _updateActionLabel(UpdateService updateService) {
    if (updateService.awaitingInstallPermission) {
      return 'อนุญาตการติดตั้ง';
    }
    switch (updateService.state) {
      case UpdateFlowState.downloading:
        final progress = (updateService.downloadProgress * 100).toStringAsFixed(
          0,
        );
        return 'กำลังดาวน์โหลด $progress%';
      case UpdateFlowState.readyToInstall:
      case UpdateFlowState.downloaded:
      case UpdateFlowState.installing:
        return 'ติดตั้งอัปเดต';
      default:
        return 'อัปเดตแอป';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('บัญชีผู้ใช้')),
      body: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          widget.authController,
          widget.updateService,
        ]),
        builder: (context, _) {
          final email =
              widget.authController.currentUser?.email?.trim().isNotEmpty ==
                  true
              ? widget.authController.currentUser!.email!
              : 'ยังไม่ได้เข้าสู่ระบบ';
          final packageStatus = SessionPackageStatus.fromExpiresAt(
            widget.authController.currentSubscription?.expiryDate,
          );
          final statusColor = packageStatus.hasPackage
              ? const Color(0xFFE62117)
              : Colors.black87;
          final customerLevel = _customerLevelLabel(
            widget.authController.currentSubscription?.plan,
          );
          final updateService = widget.updateService;
          final currentVersionText = updateService.currentVersionCode > 0
              ? '${updateService.currentVersionName} (${updateService.currentVersionCode})'
              : updateService.currentVersionName;
          final latestManifest = updateService.manifest;
          final latestVersionText = latestManifest == null
              ? 'ยังไม่มีข้อมูล'
              : '${latestManifest.latestVersionName} (${latestManifest.latestVersionCode})';
          final hasNewVersion =
              latestManifest != null &&
              latestManifest.latestVersionCode >
                  updateService.currentVersionCode;
          final updateMessage = updateService.message.trim();

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${packageStatus.tabStatusLabel} • ${packageStatus.remainingDaysLabel}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('อีเมลที่เข้าสู่ระบบ'),
                subtitle: Text(email),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('ระดับลูกค้า'),
                subtitle: Text(customerLevel),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F6F6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Expanded(
                          child: Text(
                            'อัปเดตแอป',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: updateService.isBusy
                              ? null
                              : _runUpdateFlow,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE62117),
                            foregroundColor: Colors.white,
                          ),
                          icon:
                              updateService.state == UpdateFlowState.downloading
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.system_update_alt, size: 18),
                          label: Text(_updateActionLabel(updateService)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('เวอร์ชันที่ใช้งาน: $currentVersionText'),
                    const SizedBox(height: 4),
                    Text(
                      'เวอร์ชันล่าสุด: $latestVersionText',
                      style: TextStyle(
                        color: hasNewVersion
                            ? const Color(0xFFE62117)
                            : Colors.black87,
                        fontWeight: hasNewVersion
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    if (updateService.state == UpdateFlowState.downloading) ...[
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: updateService.downloadProgress > 0
                            ? updateService.downloadProgress
                            : null,
                        minHeight: 6,
                      ),
                    ],
                    if (updateMessage.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        updateMessage,
                        style: TextStyle(
                          color: updateService.state == UpdateFlowState.error
                              ? Colors.red.shade700
                              : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    _showPlaceholderMessage(AccountPlaceholders.topUpMessage),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE62117),
                ),
                icon: const Icon(Icons.add_card_outlined),
                label: const Text('เติมวันใช้งาน'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('ตั้งค่า'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isSigningOut ? null : _signOut,
                icon: _isSigningOut
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout),
                label: const Text('ออกจากระบบ'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _contactAdminViaLine,
                icon: const Icon(Icons.support_agent_outlined),
                label: const Text('ติดต่อแอดมิน (LINE)'),
              ),
            ],
          );
        },
      ),
    );
  }
}
