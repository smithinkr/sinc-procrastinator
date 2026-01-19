import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/task_model.dart';

class NaturalLanguageParser {
  
  static Task parse(String input) {
    String lowerInput = input.toLowerCase().trim();
    String cleanTitle = input; 
    DateTime now = DateTime.now();
    DateTime todayMidnight = DateTime(now.year, now.month, now.day);
    
    DateTime? exactDate;
    bool hasSpecificTime = false;
    String priority = 'Medium';
    TimeOfDay? extractedTime;

    // --- 1. PRIORITY DETECTION ---
    if (lowerInput.contains('urgent') || lowerInput.contains('asap') || lowerInput.contains('important') || lowerInput.contains('!!!')) {
      priority = 'High';
      cleanTitle = _removePhrase(cleanTitle, ['urgent', 'asap', 'important', '!!!']);
    } else if (lowerInput.contains('maybe') || lowerInput.contains('sometime')) {
      priority = 'Low';
    }

    // --- 2. TIME DETECTION ---
    final timeRegex = RegExp(r'\b(?:at|by|for|until)?\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)\b');
    final matchTime = timeRegex.firstMatch(lowerInput);

    if (matchTime != null) {
      int hour = int.parse(matchTime.group(1)!);
      int minute = matchTime.group(2) != null ? int.parse(matchTime.group(2)!) : 0;
      String period = matchTime.group(3)!.replaceAll('.', ''); 

      if (period == 'pm' && hour < 12) hour += 12;
      if (period == 'am' && hour == 12) hour = 0;

      extractedTime = TimeOfDay(hour: hour, minute: minute);
      hasSpecificTime = true;
      cleanTitle = cleanTitle.replaceAll(matchTime.group(0)!, ''); 
    } else {
      final militaryRegex = RegExp(r'\b(\d{1,2}):(\d{2})\b');
      final matchMilitary = militaryRegex.firstMatch(lowerInput);
      if (matchMilitary != null) {
        int hour = int.parse(matchMilitary.group(1)!);
        int minute = int.parse(matchMilitary.group(2)!);
        extractedTime = TimeOfDay(hour: hour, minute: minute);
        hasSpecificTime = true;
        cleanTitle = cleanTitle.replaceAll(matchMilitary.group(0)!, '');
      }
    }

    // --- 3. DATE DETECTION (Priority Order) ---
    
    // A. Day After Tomorrow (MUST BE CHECKED BEFORE TOMORROW)
    final dayAfterTmrwRegex = RegExp(r'\b(?:on|for|by)?\s*(day after tomorrow)\b');
    // B. Relative Days
    final tmrwRegex = RegExp(r'\b(?:for|by|due|on)?\s*(tomorrow|tmrw)\b');
    final todayRegex = RegExp(r'\b(?:for|by|due|on)?\s*(today)\b');

    if (dayAfterTmrwRegex.hasMatch(lowerInput)) {
      exactDate = todayMidnight.add(const Duration(days: 2));
      cleanTitle = cleanTitle.replaceAll(dayAfterTmrwRegex.stringMatch(lowerInput)!, '');
    } 
    else if (tmrwRegex.hasMatch(lowerInput)) {
      exactDate = todayMidnight.add(const Duration(days: 1));
      cleanTitle = cleanTitle.replaceAll(tmrwRegex.stringMatch(lowerInput)!, '');
    } 
    else if (todayRegex.hasMatch(lowerInput)) {
      exactDate = todayMidnight;
      cleanTitle = cleanTitle.replaceAll(todayRegex.stringMatch(lowerInput)!, '');
    } 
    // C. "In X Days"
    else {
      final inDaysRegex = RegExp(r'\bin\s+(\d+)\s+(day|days|week|weeks)\b');
      final matchIn = inDaysRegex.firstMatch(lowerInput);
      if (matchIn != null) {
        int amount = int.parse(matchIn.group(1)!);
        if (matchIn.group(2)!.contains('week')) amount *= 7;
        exactDate = todayMidnight.add(Duration(days: amount));
        cleanTitle = cleanTitle.replaceAll(matchIn.group(0)!, '');
      } else {
        // D. Specific Weekdays
        var weekdayResult = _findNextWeekday(lowerInput);
        if (weekdayResult != null) {
          exactDate = weekdayResult.date;
          cleanTitle = cleanTitle.replaceAll(RegExp(weekdayResult.detectedString, caseSensitive: false), '');
        }
      }
    }

    // --- 4. MERGE DATE & TIME ---
    DateTime? finalDateTime;
    if (exactDate != null) {
      finalDateTime = DateTime(
        exactDate.year, exactDate.month, exactDate.day, 
        extractedTime?.hour ?? 9, extractedTime?.minute ?? 0
      );
    } else if (hasSpecificTime && extractedTime != null) {
      // If time provided but no date, assume today (or tomorrow if time passed)
      final target = DateTime(now.year, now.month, now.day, extractedTime.hour, extractedTime.minute);
      finalDateTime = target.isBefore(now) ? target.add(const Duration(days: 1)) : target;
    }

    // --- 5. FORMAT DISPLAY ---
    String displayDate = "";
    if (finalDateTime != null) {
      const List<String> months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
      displayDate = "${months[finalDateTime.month - 1]} ${finalDateTime.day}"; 
      if (hasSpecificTime) {
        String period = finalDateTime.hour >= 12 ? "PM" : "AM";
        int hour12 = finalDateTime.hour > 12 ? finalDateTime.hour - 12 : (finalDateTime.hour == 0 ? 12 : finalDateTime.hour);
        displayDate += " $hour12:${finalDateTime.minute.toString().padLeft(2, '0')} $period";
      }
    }

    cleanTitle = cleanTitle.replaceAll(RegExp(r'\s+'), ' ').trim();

    return Task(
      id: const Uuid().v4(),
      title: cleanTitle.isEmpty ? input : cleanTitle,
      category: 'General', 
      priority: priority,
      subtasks: [], 
      isCompleted: false,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      dueDate: displayDate,
      exactDate: finalDateTime,
      hasSpecificTime: hasSpecificTime,
      isAiGenerated: false,
    );
  }

  static String _removePhrase(String input, List<String> phrases) {
    String output = input;
    for (var p in phrases) {
      output = output.replaceAll(RegExp(r'\b' + RegExp.escape(p) + r'\b', caseSensitive: false), '');
    }
    return output;
  }

  static WeekdayMatch? _findNextWeekday(String input) {
    Map<String, int> days = {
      'monday': 1, 'mon': 1, 'tuesday': 2, 'tue': 2, 'wednesday': 3, 'wed': 3,
      'thursday': 4, 'thu': 4, 'friday': 5, 'fri': 5, 'saturday': 6, 'sat': 6, 'sunday': 7, 'sun': 7
    };

    for (var entry in days.entries) {
      final regex = RegExp(r'\b(?:next|on|for|by)?\s*(' + RegExp.escape(entry.key) + r')\b', caseSensitive: false);
      final match = regex.firstMatch(input);

      if (match != null) {
        int targetWeekday = entry.value;
        DateTime now = DateTime.now();
        int currentWeekday = now.weekday;
        
        // Logic: How many days to add to get to that weekday?
        int daysToAdd = (targetWeekday - currentWeekday + 7) % 7;
        
        String fullMatch = match.group(0)!.toLowerCase();
        
        // If it's today and they say "friday" (and today IS friday), assume next week
        // OR if they explicitly say "next friday"
        if (fullMatch.contains('next') || daysToAdd == 0) {
          daysToAdd += 7;
        }
        
        return WeekdayMatch(
          DateTime(now.year, now.month, now.day).add(Duration(days: daysToAdd)), 
          match.group(0)!
        );
      }
    }
    return null;
  }
}

class WeekdayMatch {
  final DateTime date;
  final String detectedString;
  WeekdayMatch(this.date, this.detectedString);
}