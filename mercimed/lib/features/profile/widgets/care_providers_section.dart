import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/models/hospital.dart';
import '../../../shared/theme/app_theme.dart';

/// Live list of OCIC-affiliated partner hospitals. Pulls every hospital row
/// (single `.eq()` on `is_ocic_affiliated` isn't worth a dedicated stream)
/// and filters client-side; the column defaults to `false` when missing so
/// the section just renders empty if the backend migration hasn't applied.
final _ocicHospitalsProvider = FutureProvider.autoDispose<List<Hospital>>((
  ref,
) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('hospitals')
      .select()
      .order('name', ascending: true);
  return (rows as List)
      .cast<Map<String, dynamic>>()
      .map(Hospital.fromJson)
      .where((h) => h.isOcicAffiliated)
      .toList();
});

/// Rendered below the FAMILY section on the profile screen. Lists partner
/// hospitals with phone / Telegram / map-direction shortcuts. Renders empty
/// when the directory is unpopulated.
class CareProvidersSection extends ConsumerWidget {
  const CareProvidersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_ocicHospitalsProvider);
    return async.when(
      loading: () => const _EmptyHint('Loading partner hospitals…'),
      error: (e, _) => _EmptyHint('Could not load partner hospitals.'),
      data: (hospitals) {
        if (hospitals.isEmpty) {
          return const _EmptyHint('No partner hospitals configured yet.');
        }
        return Column(
          children: [
            for (var i = 0; i < hospitals.length; i++) ...[
              _HospitalCard(hospital: hospitals[i]),
              if (i < hospitals.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.local_hospital_outlined,
            color: AppTheme.muted,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF6B7C8C),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HospitalCard extends StatelessWidget {
  final Hospital hospital;
  const _HospitalCard({required this.hospital});

  Future<void> _call() async {
    final phone = hospital.phone;
    if (phone == null || phone.trim().isEmpty) return;
    final clean = phone.replaceAll(RegExp(r'\s+'), '');
    await launchUrl(Uri(scheme: 'tel', path: clean));
  }

  Future<void> _telegram() async {
    final handle = hospital.telegramHandle?.trim();
    if (handle == null || handle.isEmpty) return;
    final clean = handle.startsWith('@') ? handle.substring(1) : handle;
    await launchUrl(
      Uri.parse('https://t.me/$clean'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _directions() async {
    final lat = hospital.latitude;
    final lng = hospital.longitude;
    Uri uri;
    if (lat != null && lng != null) {
      if (!kIsWeb && Platform.isAndroid) {
        uri = Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(hospital.name)})');
      } else {
        uri = Uri.parse('https://maps.apple.com/?q=$lat,$lng');
      }
    } else {
      final q = Uri.encodeComponent(hospital.address ?? hospital.name);
      uri = Uri.parse('https://maps.apple.com/?q=$q');
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = (hospital.phone ?? '').trim().isNotEmpty;
    final hasTelegram = (hospital.telegramHandle ?? '').trim().isNotEmpty;
    final hasMap = hospital.latitude != null ||
        (hospital.address ?? '').trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryDark.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _HospitalLogo(url: hospital.logoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hospital.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.primaryDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if ((hospital.khmerName ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        hospital.khmerName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF6B7C8C),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if ((hospital.address ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        hospital.address!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF6B7C8C),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ContactIconButton(
                icon: Icons.call_rounded,
                label: 'Call',
                enabled: hasPhone,
                onTap: _call,
              ),
              const SizedBox(width: 10),
              _ContactIconButton(
                icon: Icons.send_rounded,
                label: 'Telegram',
                enabled: hasTelegram,
                onTap: _telegram,
              ),
              const SizedBox(width: 10),
              _ContactIconButton(
                icon: Icons.directions_rounded,
                label: 'Directions',
                enabled: hasMap,
                onTap: _directions,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HospitalLogo extends StatelessWidget {
  final String? url;
  const _HospitalLogo({required this.url});

  @override
  Widget build(BuildContext context) {
    const size = 48.0;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.teal.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.local_hospital_rounded,
        color: AppTheme.teal,
        size: 24,
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}

class _ContactIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _ContactIconButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: enabled ? 1.0 : 0.4,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.teal.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.teal.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: AppTheme.teal, size: 18),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppTheme.teal,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
