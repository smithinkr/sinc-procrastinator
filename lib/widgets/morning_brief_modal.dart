import 'dart:ui';
import 'package:flutter/material.dart';

class MorningBriefModal extends StatelessWidget {
  final String brief;

  const MorningBriefModal({super.key, required this.brief});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: AlertDialog(
        backgroundColor: Colors.white.withValues(alpha: 0.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        title: const Text("morning brief", style: TextStyle(fontWeight: FontWeight.w300)),
        content: Text(
          brief.toLowerCase(), // Keeping your minimalist lowercase style
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("let's go", style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}