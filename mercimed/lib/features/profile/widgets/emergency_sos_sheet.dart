import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/app_bottom_sheet.dart';

/// Cambodia national emergency numbers (verified, stable):
///   119 — Ambulance
///   117 — Police
///   118 — Fire
const _kAmbulance = '119';
const _kPolice = '117';
const _kFire = '118';

// Tourist police numbers per province (verified, stable).
const _kTouristPP = ['023 726 158', '097 778 0002'];
const _kTouristSR = ['012 402 424', '012 969 991'];

/// Shows the Emergency SOS sheet — three top-level dial tiles plus a small
/// Tourist Police disclosure. Every tap presents a confirmation dialog before
/// launching the dialer; we never bypass it (Apple/Google policies, but also
/// because misdial is a real worry on a medical app).
Future<void> showEmergencySosSheet(BuildContext context) {
  return showAppBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 8, 4),
                child: Text(
                  'Emergency SOS',
                  style: TextStyle(
                    color: AppTheme.primaryDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 8, 14),
                child: Text(
                  'Cambodia national emergency numbers. Tap to dial — you\'ll still need to confirm in your phone.',
                  style: TextStyle(
                    color: Color(0xFF6B7C8C),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
              _SosTile(
                primary: true,
                icon: Icons.local_hospital_rounded,
                label: 'Ambulance',
                number: _kAmbulance,
                onTap: () => _confirmDial(ctx, _kAmbulance, 'Ambulance'),
              ),
              const SizedBox(height: 10),
              _SosTile(
                icon: Icons.local_police_rounded,
                label: 'Police',
                number: _kPolice,
                onTap: () => _confirmDial(ctx, _kPolice, 'Police'),
              ),
              const SizedBox(height: 10),
              _SosTile(
                icon: Icons.local_fire_department_rounded,
                label: 'Fire',
                number: _kFire,
                onTap: () => _confirmDial(ctx, _kFire, 'Fire'),
              ),
              const SizedBox(height: 14),
              _TouristPoliceTile(
                onTap: () => _showTouristPoliceDialog(ctx),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _confirmDial(
  BuildContext context,
  String number,
  String label,
) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (dctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text('Call $label — $number?'),
      content: Text(
        "Open dialer to call $number? You'll still need to tap the call button on your phone.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dctx, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(dctx, true),
          icon: const Icon(Icons.call_rounded, size: 16),
          label: const Text('Open dialer'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD64B4B),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  // Strip spaces so 023 726 158 → 023726158.
  final clean = number.replaceAll(RegExp(r'\s+'), '');
  await launchUrl(Uri(scheme: 'tel', path: clean));
}

Future<void> _showTouristPoliceDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (dctx) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Tourist Police',
              style: TextStyle(
                color: AppTheme.primaryDark,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            const _TouristGroupLabel('Phnom Penh'),
            for (final n in _kTouristPP) ...[
              const SizedBox(height: 6),
              _TouristNumberRow(
                number: n,
                onTap: () => _confirmDial(dctx, n, 'Tourist Police (PP)'),
              ),
            ],
            const SizedBox(height: 14),
            const _TouristGroupLabel('Siem Reap'),
            for (final n in _kTouristSR) ...[
              const SizedBox(height: 6),
              _TouristNumberRow(
                number: n,
                onTap: () => _confirmDial(dctx, n, 'Tourist Police (SR)'),
              ),
            ],
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(dctx),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SosTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String number;
  final bool primary;
  final VoidCallback onTap;

  const _SosTile({
    required this.icon,
    required this.label,
    required this.number,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: primary ? 20 : 14,
          ),
          decoration: BoxDecoration(
            color: primary ? AppTheme.teal.withValues(alpha: 0.10) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: primary
                  ? AppTheme.teal.withValues(alpha: 0.45)
                  : AppTheme.primaryDark.withValues(alpha: 0.06),
              width: primary ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: primary ? 50 : 40,
                height: primary ? 50 : 40,
                decoration: BoxDecoration(
                  color: (primary ? AppTheme.teal : AppTheme.primaryDark)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  color: primary ? AppTheme.teal : AppTheme.primaryDark,
                  size: primary ? 26 : 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: AppTheme.primaryDark,
                        fontSize: primary ? 17 : 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Call $number',
                      style: const TextStyle(
                        color: Color(0xFF6B7C8C),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: primary ? AppTheme.teal : const Color(0xFFEEF1F5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  number,
                  style: TextStyle(
                    color: primary ? Colors.white : AppTheme.primaryDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TouristPoliceTile extends StatelessWidget {
  final VoidCallback onTap;
  const _TouristPoliceTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.primaryDark.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.travel_explore_rounded,
                color: AppTheme.primaryDark,
                size: 18,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Tourist Police (PP / Siem Reap)',
                  style: TextStyle(
                    color: AppTheme.primaryDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF6B7C8C),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TouristGroupLabel extends StatelessWidget {
  final String label;
  const _TouristGroupLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF4A5568),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
      ),
    );
  }
}

class _TouristNumberRow extends StatelessWidget {
  final String number;
  final VoidCallback onTap;
  const _TouristNumberRow({required this.number, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF1F5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.call_rounded,
                size: 14,
                color: AppTheme.primaryDark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  number,
                  style: const TextStyle(
                    color: AppTheme.primaryDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: Color(0xFF6B7C8C),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
