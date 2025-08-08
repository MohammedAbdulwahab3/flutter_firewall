import 'dart:convert';
import 'package:http/http.dart' as http;
import 'denylist_local_repo.dart';

class NextDnsService {
  /// Get the current denylist from NextDNS profile as a list of domain strings.
  static Future<List<String>> getDenylist({
    required String profileId,
    required String apiKey,
  }) async {
    final url = Uri.parse('https://api.nextdns.io/profiles/$profileId/');
    final resp = await http.get(
      url,
      headers: {'X-Api-Key': apiKey, 'Accept': 'application/json'},
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('NextDNS GET failed ${resp.statusCode}: ${resp.body}');
    }
    if (resp.body.isEmpty) return <String>[];
    final Map<String, dynamic> profile =
        jsonDecode(resp.body) as Map<String, dynamic>;
    final List<dynamic> raw =
        (profile['denylist'] is List)
            ? List<dynamic>.from(profile['denylist'])
            : <dynamic>[];
    final List<String> result = [];
    for (final e in raw) {
      if (e is String)
        result.add(e.toLowerCase());
      else if (e is Map && e['id'] != null)
        result.add((e['id'] as String).toLowerCase());
    }
    // update local cache
    await DenylistLocalRepo.instance.saveAll(result);
    return result;
  }

  /// Add a single domain to the profile denylist (server-side) and update local repo.
  static Future<void> addToDenylist({
    required String profileId,
    required String apiKey,
    required String domain,
  }) async {
    final normalized = domain.trim().toLowerCase();
    if (normalized.isEmpty) throw Exception('Domain is empty');

    final url = Uri.parse('https://api.nextdns.io/profiles/$profileId/');

    // GET existing
    final getResp = await http.get(
      url,
      headers: {'X-Api-Key': apiKey, 'Accept': 'application/json'},
    );
    if (getResp.statusCode < 200 || getResp.statusCode >= 300) {
      throw Exception(
        'NextDNS GET failed ${getResp.statusCode}: ${getResp.body}',
      );
    }

    // Parse existing denylist into object list form
    final Map<String, dynamic> profile =
        getResp.body.isNotEmpty
            ? jsonDecode(getResp.body) as Map<String, dynamic>
            : {};
    final List<dynamic> raw =
        (profile['denylist'] is List)
            ? List<dynamic>.from(profile['denylist'])
            : <dynamic>[];

    // Normalize and detect duplicates
    final Set<String> ids = {};
    final List<Map<String, dynamic>> merged = [];
    for (final e in raw) {
      if (e is String) {
        ids.add(e.toLowerCase());
        merged.add({'id': e.toLowerCase(), 'active': true});
      } else if (e is Map) {
        final id = (e['id'] ?? '').toString().toLowerCase();
        if (id.isNotEmpty && !ids.contains(id)) {
          ids.add(id);
          merged.add({'id': id, 'active': e['active'] == true});
        }
      }
    }

    if (ids.contains(normalized)) {
      // already present -> update local repo and exit
      final local = merged.map((m) => m['id'] as String).toList();
      await DenylistLocalRepo.instance.saveAll(local);
      return;
    }

    merged.add({'id': normalized, 'active': true});

    // PATCH only `denylist` field (object list)
    final patchBody = jsonEncode({'denylist': merged});
    final patchResp = await http.patch(
      url,
      headers: {'X-Api-Key': apiKey, 'Content-Type': 'application/json'},
      body: patchBody,
    );

    if (patchResp.statusCode < 200 || patchResp.statusCode >= 300) {
      throw Exception(
        'NextDNS PATCH failed ${patchResp.statusCode}: ${patchResp.body}',
      );
    }

    // update local
    final updatedLocal = merged.map((m) => (m['id'] as String)).toList();
    await DenylistLocalRepo.instance.saveAll(updatedLocal);
  }

  /// Remove a domain from the profile denylist (server-side) and update local repo.
  static Future<void> removeFromDenylist({
    required String profileId,
    required String apiKey,
    required String domain,
  }) async {
    final normalized = domain.trim().toLowerCase();
    if (normalized.isEmpty) throw Exception('Domain is empty');

    final url = Uri.parse('https://api.nextdns.io/profiles/$profileId/');
    final getResp = await http.get(
      url,
      headers: {'X-Api-Key': apiKey, 'Accept': 'application/json'},
    );
    if (getResp.statusCode < 200 || getResp.statusCode >= 300) {
      throw Exception(
        'NextDNS GET failed ${getResp.statusCode}: ${getResp.body}',
      );
    }

    final Map<String, dynamic> profile =
        getResp.body.isNotEmpty
            ? jsonDecode(getResp.body) as Map<String, dynamic>
            : {};
    final List<dynamic> raw =
        (profile['denylist'] is List)
            ? List<dynamic>.from(profile['denylist'])
            : <dynamic>[];

    final List<Map<String, dynamic>> merged = [];
    for (final e in raw) {
      if (e is String) {
        final id = e.toLowerCase();
        if (id != normalized) merged.add({'id': id, 'active': true});
      } else if (e is Map) {
        final id = (e['id'] ?? '').toString().toLowerCase();
        if (id.isNotEmpty && id != normalized)
          merged.add({'id': id, 'active': e['active'] == true});
      }
    }

    final patchBody = jsonEncode({'denylist': merged});
    final patchResp = await http.patch(
      url,
      headers: {'X-Api-Key': apiKey, 'Content-Type': 'application/json'},
      body: patchBody,
    );

    if (patchResp.statusCode < 200 || patchResp.statusCode >= 300) {
      throw Exception(
        'NextDNS PATCH failed ${patchResp.statusCode}: ${patchResp.body}',
      );
    }

    // update local
    final local = merged.map((m) => (m['id'] as String)).toList();
    await DenylistLocalRepo.instance.saveAll(local);
  }

  /// Sync local repo -> remote, merging (use if you allowed local-only edits offline)
  static Future<void> syncLocalToRemote({
    required String profileId,
    required String apiKey,
  }) async {
    final local = DenylistLocalRepo.instance.getAll();
    final remote = await getDenylist(profileId: profileId, apiKey: apiKey);
    // merge sets (remote wins for duplication, just combine)
    final mergedSet = <String>{};
    mergedSet.addAll(remote.map((e) => e.toLowerCase()));
    mergedSet.addAll(local.map((e) => e.toLowerCase()));
    final mergedList = mergedSet.map((s) => {'id': s, 'active': true}).toList();
    final url = Uri.parse('https://api.nextdns.io/profiles/$profileId/');
    final patchResp = await http.patch(
      url,
      headers: {'X-Api-Key': apiKey, 'Content-Type': 'application/json'},
      body: jsonEncode({'denylist': mergedList}),
    );
    if (patchResp.statusCode < 200 || patchResp.statusCode >= 300) {
      throw Exception(
        'NextDNS PATCH failed ${patchResp.statusCode}: ${patchResp.body}',
      );
    }
    await DenylistLocalRepo.instance.saveAll(
      mergedList.map((m) => m['id'] as String).toList(),
    );
  }
}
