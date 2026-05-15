import 'package:flutter/material.dart';

import '../../../shared/models/folder.dart';

/// Heuristic mapping of [folder] → a Material icon that hints at the folder's
/// medical category. Inspects the folder name + notes for keyword matches; no
/// AI involved. Returns a generic folder icon on no-match.
IconData iconForFolder(Folder folder) {
  if (folder.isChat) return Icons.chat_bubble_rounded;
  final hay = ('${folder.name} ${folder.notes ?? ''}').toLowerCase();
  bool any(List<String> kws) => kws.any(hay.contains);
  if (any(['lab', 'blood', 'test', 'panel', 'urinalysis'])) return Icons.science_rounded;
  if (any(['heart', 'cardio', 'bp', 'blood pressure', 'ecg', 'ekg'])) return Icons.monitor_heart_rounded;
  if (any(['baby', 'child', 'pediatric', 'kids', 'infant'])) return Icons.child_care_rounded;
  if (any(['eye', 'vision', 'optometry', 'optical'])) return Icons.visibility_rounded;
  if (any(['dental', 'tooth', 'teeth', 'orthodont'])) return Icons.sentiment_satisfied_rounded;
  if (any(['prescription', 'meds', 'medication', 'pharmacy', 'drug'])) return Icons.medication_rounded;
  if (any(['xray', 'x-ray', 'radiology', 'scan', 'mri', 'ct'])) return Icons.medical_services_rounded;
  if (any(['vaccine', 'immunization', 'vaccination', 'shot'])) return Icons.vaccines_rounded;
  if (any(['pregnancy', 'maternity', 'prenatal', 'ob/gyn', 'gyno'])) return Icons.pregnant_woman_rounded;
  if (any(['mental', 'therapy', 'psych', 'counsel'])) return Icons.psychology_rounded;
  if (any(['allerg', 'asthma'])) return Icons.air_rounded;
  return Icons.folder_rounded;
}
