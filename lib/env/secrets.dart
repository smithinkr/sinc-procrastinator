import 'package:envied/envied.dart';

part 'secrets.g.dart';

@Envied(path: 'lib/env/.env', obfuscate: true)
abstract class Secrets {
  @EnviedField(varName: 'GEMINI_API_KEY')
  static final String geminiApiKey = _Secrets.geminiApiKey; // Use _Secrets, not _Env
}