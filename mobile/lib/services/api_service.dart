import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:http/http.dart' as http;
import '../models/models.dart';

/// Thin HTTP client for the Career AI backend.
///
/// Set [baseUrl] for your environment:
///   - Android emulator:  http://10.0.2.2:8077
///   - iOS simulator:     http://127.0.0.1:8077
///   - physical device:   http://<your-machine-LAN-IP>:8077
class ApiService {
  ApiService({String? baseUrl}) : baseUrl = baseUrl ?? defaultBaseUrl;

  // Override at build time for real devices / production:
  //   flutter build ios --dart-define=API_BASE_URL=https://api.votre-domaine.com
  // Defaults: web & iOS simulator reach the Mac at 127.0.0.1; Android emulator
  // uses 10.0.2.2. A physical iPhone must use the Mac's LAN IP or a deployed URL.
  static final String defaultBaseUrl = _resolveBaseUrl();

  static String _resolveBaseUrl() {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) return override;
    if (kIsWeb) return 'http://127.0.0.1:8077';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8077';
      case TargetPlatform.iOS:
        return 'http://127.0.0.1:8077'; // simulator; override for a real iPhone
      default:
        return 'http://127.0.0.1:8077';
    }
  }
  final String baseUrl;
  String? _token;

  /// Called when the server rejects our token (HTTP 401) on an authenticated
  /// request — lets [AppState] clear the stale session and return to login.
  void Function()? onUnauthorized;

  void setToken(String? token) => _token = token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Uri _u(String path, [Map<String, dynamic>? q]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: q?.map((k, v) => MapEntry(k, '$v')));

  dynamic _decode(http.Response r) {
    final body = r.body.isEmpty ? {} : jsonDecode(r.body);
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    // A 401 on a call we made *with* a token means the token is stale/expired
    // (e.g. backend restarted or DB reset) — drop the session cleanly.
    if (r.statusCode == 401 && _token != null) onUnauthorized?.call();
    final detail = (body is Map && body['detail'] != null) ? body['detail'] : 'Erreur ${r.statusCode}';
    throw ApiException(detail.toString(), r.statusCode);
  }

  // ---------- auth ----------
  Future<AuthResult> register(String email, String password, String name, String role,
      {bool consent = false}) async {
    final r = await http.post(_u('/auth/register'),
        headers: _headers,
        body: jsonEncode({'email': email, 'password': password, 'name': name,
            'role': role, 'consent': consent}));
    final j = _decode(r);
    return AuthResult(j['token'], AppUser.fromJson(j['user']));
  }

  Future<AuthResult> login(String email, String password) async {
    final r = await http.post(_u('/auth/login'),
        headers: _headers, body: jsonEncode({'email': email, 'password': password}));
    final j = _decode(r);
    return AuthResult(j['token'], AppUser.fromJson(j['user']));
  }

  // ---------- CV ----------
  Future<Map<String, dynamic>> uploadCvText(String text, {String? title, String? location}) async {
    final req = http.MultipartRequest('POST', _u('/cv/upload'));
    req.headers['Authorization'] = 'Bearer $_token';
    req.fields['text'] = text;
    if (title != null) req.fields['title'] = title;
    if (location != null) req.fields['location'] = location;
    final r = await http.Response.fromStream(await req.send());
    return _decode(r);
  }

  Future<Map<String, dynamic>> uploadCvFile(List<int> bytes, String filename,
      {String? title, String? location}) async {
    final req = http.MultipartRequest('POST', _u('/cv/upload'));
    req.headers['Authorization'] = 'Bearer $_token';
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    if (title != null) req.fields['title'] = title;
    if (location != null) req.fields['location'] = location;
    final r = await http.Response.fromStream(await req.send());
    return _decode(r);
  }

  Future<Map<String, dynamic>> getCv() async {
    final r = await http.get(_u('/cv'), headers: _headers);
    return Map<String, dynamic>.from(_decode(r));
  }

  // ---------- jobs ----------
  Future<List<Job>> jobs(
      {String query = '', String location = '', int limit = 50, bool sync = false,
      bool syncProfile = false, bool favoritesOnly = false,
      String contract = '', bool remote = false, String sort = 'match',
      bool alternance = false}) async {
    final r = await http.get(
        _u('/jobs', {
          'query': query, 'location': location, 'limit': limit, 'sync': sync,
          'sync_profile': syncProfile, 'favorites_only': favoritesOnly,
          'contract': contract, 'remote': remote, 'sort': sort,
          'alternance': alternance,
        }),
        headers: _headers);
    final j = _decode(r);
    return (j['jobs'] as List).map((e) => Job.fromJson(e)).toList();
  }

  Future<bool> toggleFavorite(int jobId) async {
    final r = await http.post(_u('/favorites/$jobId'), headers: _headers);
    return _decode(r)['liked'] == true;
  }

  // ---------- activity (Duolingo-style streak) ----------
  Future<void> activityPing() async {
    try {
      await http.post(_u('/activity/ping'), headers: _headers);
    } catch (_) {/* non-blocking */}
  }

  Future<Map<String, dynamic>> activity() async {
    final r = await http.get(_u('/activity'), headers: _headers);
    return Map<String, dynamic>.from(_decode(r));
  }

  Future<List<Map<String, dynamic>>> trainingQuestions({int jobId = 0}) async {
    final r = await http.get(_u('/training/questions', {'job_id': jobId}), headers: _headers);
    final j = _decode(r);
    return List<Map<String, dynamic>>.from(j['questions']);
  }

  Future<void> trainingSaveSession(int score, Map<String, dynamic> axes, int answers) async {
    final r = await http.post(_u('/training/session'),
        headers: _headers, body: jsonEncode({'score': score, 'axes': axes, 'answers': answers}));
    _decode(r);
  }

  Future<Map<String, dynamic>> trainingHistory() async {
    final r = await http.get(_u('/training/history'), headers: _headers);
    return Map<String, dynamic>.from(_decode(r));
  }

  /// Tapping "Postuler" auto-records the application. Returns the new applied count.
  Future<int> recordApplied(int jobId) async {
    final r = await http.post(_u('/applications/applied'),
        headers: _headers, body: jsonEncode({'job_id': jobId}));
    final j = _decode(r);
    return j['applied_count'] ?? 0;
  }

  Future<Map<String, dynamic>> trainingScore(String question, String answer, String type,
      {int jobId = 0}) async {
    final r = await http.post(_u('/training/score'),
        headers: _headers,
        body: jsonEncode({'question': question, 'answer': answer, 'type': type, 'job_id': jobId}));
    return Map<String, dynamic>.from(_decode(r));
  }

  Future<Map<String, dynamic>> insights({String query = ''}) async {
    final r = await http.get(_u('/insights', {'query': query}), headers: _headers);
    return Map<String, dynamic>.from(_decode(r));
  }

  Future<Map<String, dynamic>> refreshJobs({String query = '', String location = ''}) async {
    final r = await http.post(_u('/jobs/refresh', {'query': query, 'location': location}),
        headers: _headers);
    return Map<String, dynamic>.from(_decode(r));
  }

  Future<void> postJob(Map<String, dynamic> job) async {
    final r = await http.post(_u('/jobs/post'), headers: _headers, body: jsonEncode(job));
    _decode(r);
  }

  // ---------- applications ----------
  Future<List<Map<String, dynamic>>> autoApply(List<int> jobIds) async {
    final r = await http.post(_u('/applications/auto'),
        headers: _headers, body: jsonEncode({'job_ids': jobIds}));
    final j = _decode(r);
    return List<Map<String, dynamic>>.from(j['created']);
  }

  Future<void> validateApplication(int id) async {
    _decode(await http.post(_u('/applications/$id/validate'), headers: _headers));
  }

  Future<void> rejectApplication(int id) async {
    _decode(await http.post(_u('/applications/$id/reject'), headers: _headers));
  }

  Future<void> markApplied(int id) async {
    _decode(await http.post(_u('/applications/$id/applied'), headers: _headers));
  }

  Future<Map<String, dynamic>> requestPlacement(int candidateId, String message) async {
    final r = await http.post(_u('/talents/$candidateId/request'),
        headers: _headers, body: jsonEncode({'message': message}));
    return Map<String, dynamic>.from(_decode(r));
  }

  Future<Map<String, dynamic>> scheduleInterview(
      int candidateId, String scheduledAt, String teamsLink, String message) async {
    final r = await http.post(_u('/recruiter/interview'),
        headers: _headers,
        body: jsonEncode({'candidate_id': candidateId, 'scheduled_at': scheduledAt,
            'teams_link': teamsLink, 'message': message}));
    return Map<String, dynamic>.from(_decode(r));
  }

  Future<List<Map<String, dynamic>>> myInterviews() async {
    final r = await http.get(_u('/me/interviews'), headers: _headers);
    final j = _decode(r);
    return List<Map<String, dynamic>>.from(j['interviews']);
  }

  Future<void> respondInterview(int id, bool accept) async {
    _decode(await http.post(_u('/interviews/$id/respond', {'accept': accept}), headers: _headers));
  }

  Future<void> deleteAccount() async {
    _decode(await http.delete(_u('/me'), headers: _headers));
  }

  Future<List<Application>> applications() async {
    final r = await http.get(_u('/applications'), headers: _headers);
    final j = _decode(r);
    return (j['applications'] as List).map((e) => Application.fromJson(e)).toList();
  }

  // ---------- recruiter ----------
  Future<Map<String, dynamic>> talentAccessStatus() async {
    final r = await http.get(_u('/recruiter/access-status'), headers: _headers);
    return Map<String, dynamic>.from(_decode(r));
  }

  Future<Map<String, dynamic>> requestTalentAccess(
      String company, String phone, String message) async {
    final r = await http.post(_u('/recruiter/request-access'),
        headers: _headers,
        body: jsonEncode({'company': company, 'phone': phone, 'message': message}));
    return Map<String, dynamic>.from(_decode(r));
  }

  Future<List<Candidate>> talents({String query = '', int? jobId}) async {
    final q = {'query': query, if (jobId != null) 'job_id': jobId};
    final r = await http.get(_u('/talents', q), headers: _headers);
    final j = _decode(r);
    return (j['candidates'] as List).map((e) => Candidate.fromJson(e)).toList();
  }

  // ---------- dashboards ----------
  Future<SeekerDashboard> seekerDashboard() async {
    final r = await http.get(_u('/dashboard/seeker'), headers: _headers);
    return SeekerDashboard.fromJson(_decode(r));
  }

  Future<RecruiterDashboard> recruiterDashboard() async {
    final r = await http.get(_u('/dashboard/recruiter'), headers: _headers);
    return RecruiterDashboard.fromJson(_decode(r));
  }
}

class AuthResult {
  final String token;
  final AppUser user;
  AuthResult(this.token, this.user);
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, this.statusCode);
  @override
  String toString() => message;
}
