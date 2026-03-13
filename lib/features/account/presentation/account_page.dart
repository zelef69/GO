import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes/app_routes.dart';
import '../../auth/auth_controller.dart';
import '../../auth/domain/session_package_status.dart';
import '../account_placeholders.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({required this.authController, super.key});

  final AuthController authController;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  static final Uri _lineContactUri = Uri.parse(
    'https://line.me/R/ti/p/%40615yysio',
  );

  bool _isSigningOut = false;
  Timer? _countdownTicker;

  @override
  void initState() {
    super.initState();
    _countdownTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    _countdownTicker = null;
    super.dispose();
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

  String _expiryDateLabel(DateTime? expiresAtUtc) {
    if (expiresAtUtc == null) {
      return '-';
    }
    final local = expiresAtUtc.toLocal();
    final yyyy = local.year.toString().padLeft(4, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: AnimatedBuilder(
        animation: widget.authController,
        builder: (context, _) {
          final email =
              widget.authController.currentUser?.email?.trim().isNotEmpty ==
                  true
              ? widget.authController.currentUser!.email!
              : 'Not signed in';
          final packageStatus = SessionPackageStatus.fromExpiresAt(
            widget.authController.currentSubscription?.expiryDate,
          );
          final statusColor = packageStatus.hasPackage
              ? const Color(0xFFE62117)
              : Colors.black87;

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
                title: const Text('Login Email'),
                subtitle: Text(email),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Remaining Usage Days'),
                subtitle: Text(packageStatus.remainingDaysLabel),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Expiry Date (วันหมดอายุ)'),
                subtitle: Text(_expiryDateLabel(packageStatus.expiresAtUtc)),
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
                label: const Text('Settings'),
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
                label: const Text('Sign Out'),
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
