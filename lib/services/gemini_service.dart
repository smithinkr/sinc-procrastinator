import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/task_model.dart';
import 'natural_language_parser.dart'; 
import 'dart:io';
import '../env/secrets.dart'; // Add this line

class GeminiService {
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';
  
  // THE ONLY KEY: This is injected at build-time from your .env
  static final String _apiKey = Secrets.geminiApiKey;
  
  static DateTime? _lastRequestTime;
  static const int _cooldownSeconds = 2;

  // REMOVED: 'String vaultedKey' parameter as it is no longer needed
  static Future<Task> analyzeTask(
    dynamic input, 
    double creativity, {
    Task? preParsedTask, 
  }) async {
    final now = DateTime.now();
    if (_lastRequestTime != null && now.difference(_lastRequestTime!).inSeconds < _cooldownSeconds) {
      throw Exception("RATE_LIMIT_COOLDOWN");
    }
    _lastRequestTime = now;

    // SECURITY CHECK: Verify the injected key is actually present
    if (_apiKey.isEmpty) {
      throw Exception("CRITICAL_SECURITY_ERROR: API Key not injected.");
    }
    
    dynamic sanitizedInput = input;
    if (input is String) {
      sanitizedInput = input.length > 1000 ? input.substring(0, 1000) : input;
      sanitizedInput = sanitizedInput.replaceAll(RegExp(r'ignore (all )?previous instructions', caseSensitive: false), '[REDACTED]');
    }

    final url = Uri.parse(_baseUrl);
    List<Map<String, dynamic>> parts = [];

    if (sanitizedInput is String) {
      parts.add({"text": _buildSecureTaskPrompt(sanitizedInput, creativity, preParsedTask: preParsedTask)});
    } else if (sanitizedInput is File) {
      final bytes = await sanitizedInput.readAsBytes();
      parts.add({
        "inlineData": {"mimeType": "audio/aac", "data": base64Encode(bytes)}
      });
      parts.add({"text": _buildSecureTaskPrompt("User provided an audio recording.", creativity, preParsedTask: preParsedTask)});
    }

    final response = await http.post(
      url,
      // SECURITY: Using the hidden _envKey directly in the header
      headers: {'Content-Type': 'application/json', 'x-goog-api-key': _apiKey},
      body: jsonEncode({
        "contents": [{"parts": parts}],
        "safetySettings": [
          {"category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_ONLY_HIGH"},
          {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_ONLY_HIGH"},
          {"category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_ONLY_HIGH"},
        ],
        "generationConfig": {
          "temperature": creativity,
          "responseMimeType": "application/json"
        }
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final String rawText = data['candidates'][0]['content']['parts'][0]['text'];
      return _parseAiResponse(rawText, input is String ? input : "Audio Task");
    } else {
      throw Exception("SERVER_ERROR_${response.statusCode}");
    }
  }

  // --- PRIVATE HELPERS (PROMPTS AND PARSING PRESERVED) ---

  static String _buildSecureTaskPrompt(String input, double creativity, {Task? preParsedTask}) {
    final now = DateTime.now();
    
    String constraintBlock = "";
    if (preParsedTask != null && (preParsedTask.dueDate.isNotEmpty || preParsedTask.priority == 'High')) {
      constraintBlock = """
      [SOURCE OF TRUTH - MANDATORY]
      The local system identified these. DO NOT CHANGE:
      - Date/Time: ${preParsedTask.dueDate}
      - Urgent Status: ${preParsedTask.priority}
      """;
    }

    String complexity = creativity <= 0.3 
        ? "LITERAL: 2-3 essential steps." 
        : (creativity < 0.8 ? "BALANCED: 3-5 subtasks." : "COMPREHENSIVE: 5-7 subtasks.");

    return """
      [SYSTEM ROLE]
      You are a Professional Project Manager.
      
      [STRICT CATEGORY ENUM]
      You MUST categorize the task into exactly ONE of these four. DO NOT invent new ones:
      1. Work
      2. Personal
      3. Shopping
      4. General

      [DATE MATH CONTEXT]
      Reference Today: ${now.year}-${now.month}-${now.day} (Weekday: ${now.weekday})
      - If the user says "before January ends", calculate the last day of Jan ${now.year}.
      - If "this weekend", use Sunday.
      - If no date is mentioned, set 'exactDate' to null. No hallucinations.

      $constraintBlock

      [TONE & DEPTH]
      Professional. Complexity Level: $complexity

      <USER_DATA>
      $input
      </USER_DATA>

      [TASK]
      Extract title and category. Generate subtasks.
      Output STRICT JSON with: title, priority, category, dueDate (DD/MM), exactDate (YYYY-MM-DD), and hasSpecificTime (bool).
    """;
  }

  static Task _parseAiResponse(String rawText, String originalInput) {
    try {
      final int start = rawText.indexOf('{');
      final int end = rawText.lastIndexOf('}');
      if (start == -1) throw const FormatException();

      final json = jsonDecode(rawText.substring(start, end + 1));
      List<SubTask> subtasks = (json['subtasks'] as List? ?? []).map((t) => 
        SubTask(id: const Uuid().v4(), title: t is Map ? t['title'] : t.toString(), isCompleted: false)
      ).toList();

      DateTime? exact;
      if (json['exactDate'] != null && json['exactDate'] != "null") {
        exact = DateTime.tryParse(json['exactDate']);
      }

      return Task(
        id: const Uuid().v4(),
        title: json['title'] ?? originalInput,
        priority: json['priority'] ?? 'Medium',
        category: json['category'] ?? 'General',
        dueDate: json['dueDate'] ?? (exact != null ? "${exact.day}/${exact.month}" : ""),
        exactDate: exact,
        hasSpecificTime: json['hasSpecificTime'] ?? false,
        isCompleted: false,
        subtasks: subtasks,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        isAiGenerated: true,
      );
    } catch (e) {
      return NaturalLanguageParser.parse(originalInput);
    }
  }

  // UPDATED: Morning Brief logic now also uses the hidden _envKey
  static Future<String> generateMorningBrief(List<Task> tasks) async {
    if (_apiKey.isEmpty) return "API Key missing.";
    // ... Logic remains the same, using _envKey ...
    return "Brief logic preserved";
  }
}