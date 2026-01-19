import 'package:flutter/material.dart';

class CustomTextController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<InlineSpan> children = [];
    
    // IMPORTANT: "day after tomorrow" must come BEFORE "tomorrow" 
    // or the regex will cut the phrase in half!
    final pattern = RegExp(
      r'\b(day after tomorrow|tomorrow|today|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next week|urgent|asap)\b',
      caseSensitive: false,
    );

    text.splitMapJoin(
      pattern,
      onMatch: (Match match) {
        children.add(TextSpan(
          text: match[0],
          style: style?.copyWith(
            color: Colors.orangeAccent, 
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.orangeAccent.withValues(alpha: 0.1), // Subtle glow
          ),
        ));
        return "";
      },
      onNonMatch: (String text) {
        children.add(TextSpan(text: text, style: style));
        return "";
      },
    );

    return TextSpan(style: style, children: children);
  }
}