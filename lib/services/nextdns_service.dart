// // lib/services/nextdns_service.dart
// import 'dart:convert';
// import 'package:http/http.dart' as http;
// import 'denylist_local_repo.dart';

// class NextDnsService {
//   static final _base = 'https://api.nextdns.io';

//   /// List denylist entries for profile
//   static Future<List<String>> getDenylist({
//     required String profileId,
//     required String apiKey,
//   }) async {
//     final url = Uri.parse('$_base/profiles/$profileId/denylist');
//     final resp = await http.get(
//       url,
//       headers: {'X-Api-Key': apiKey, 'Accept': 'application/json'},
//     );
//     if (resp.statusCode < 200 || resp.statusCode >= 300) {
//       throw Exception(
//         'NextDNS GET denylist failed ${resp.statusCode}: ${resp.body}',
//       );
//     }
//     if (resp.body.isEmpty) return <String>[];

//     // Response shape: { "data": [ { "id": "example.com", "active": true }, ... ], "meta": {...} }
//     try {
//       final Map<String, dynamic> parsed =
//           jsonDecode(resp.body) as Map<String, dynamic>;
//       final raw = parsed['data'];
//       final List<String> out = [];
//       if (raw is List) {
//         for (final e in raw) {
//           if (e is String)
//             out.add(e.toLowerCase());
//           else if (e is Map && e['id'] != null)
//             out.add((e['id'] as String).toLowerCase());
//         }
//       } else {
//         // sometimes the API may return a raw array directly
//         if (parsed.values.isNotEmpty) {
//           // try to salvage
//         }
//       }
//       return out;
//     } catch (e) {
//       // fallback: try to decode as plain array of objects/strings
//       final dynamic raw = jsonDecode(resp.body);
//       final List<String> out = [];
//       if (raw is List) {
//         for (final e in raw) {
//           if (e is String)
//             out.add(e.toLowerCase());
//           else if (e is Map && e['id'] != null)
//             out.add((e['id'] as String).toLowerCase());
//         }
//       }
//       return out;
//     }
//   }

//   /// Replace the profile denylist with the provided list of domain strings.
//   /// Uses PUT on the arrays child endpoint (replace).
//   static Future<void> setDenylist({
//     required String profileId,
//     required String apiKey,
//     required List<String> domains,
//   }) async {
//     final normalized =
//         domains
//             .map((d) => d.trim().toLowerCase())
//             .where((d) => d.isNotEmpty)
//             .toSet()
//             .toList()
//           ..sort();
//     // Build array expected by API: [{"id":"domain","active":true}, ...]
//     final bodyList = normalized.map((s) => {'id': s, 'active': true}).toList();

//     final url = Uri.parse('$_base/profiles/$profileId/denylist');
//     final resp = await http.put(
//       url,
//       headers: {'X-Api-Key': apiKey, 'Content-Type': 'application/json'},
//       body: jsonEncode({'data': bodyList}),
//     );

//     if (resp.statusCode < 200 || resp.statusCode >= 300) {
//       // Try alternate body format (some examples POST/PUT body as array directly)
//       final resp2 = await http.put(
//         url,
//         headers: {'X-Api-Key': apiKey, 'Content-Type': 'application/json'},
//         body: jsonEncode(bodyList),
//       );
//       if (resp2.statusCode < 200 || resp2.statusCode >= 300) {
//         throw Exception(
//           'NextDNS PUT denylist failed ${resp.statusCode}: ${resp.body}',
//         );
//       }
//     }

//     // Update local cache (Hive)
//     await DenylistLocalRepo.instance.saveAll(normalized);
//   }

//   /// Add a single domain by POSTing to the denylist child endpoint.
//   static Future<void> addToDenylist({
//     required String profileId,
//     required String apiKey,
//     required String domain,
//   }) async {
//     final normalized = domain.trim().toLowerCase();
//     if (normalized.isEmpty) throw Exception('Domain is empty');

//     final url = Uri.parse('$_base/profiles/$profileId/denylist');
//     final body = jsonEncode({'id': normalized, 'active': true});
//     final resp = await http.post(
//       url,
//       headers: {'X-Api-Key': apiKey, 'Content-Type': 'application/json'},
//       body: body,
//     );

//     if (resp.statusCode < 200 || resp.statusCode >= 300) {
//       throw Exception(
//         'NextDNS POST denylist failed ${resp.statusCode}: ${resp.body}',
//       );
//     }

//     // On success update local cache: fetch remote list and persist
//     final updated = await getDenylist(profileId: profileId, apiKey: apiKey);
//     await DenylistLocalRepo.instance.saveAll(updated);
//   }

//   /// Remove a single domain. Many examples require hex:<hex> encoded id in the path.
//   /// We'll encode the domain to hex and send DELETE to /profiles/:profile/denylist/hex:<hex>
//   static Future<void> removeFromDenylist({
//     required String profileId,
//     required String apiKey,
//     required String domain,
//   }) async {
//     final normalized = domain.trim().toLowerCase();
//     if (normalized.isEmpty) throw Exception('Domain is empty');

//     // hex-encode UTF-8 bytes
//     final bytes = utf8.encode(normalized);
//     final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
//     final url = Uri.parse('$_base/profiles/$profileId/denylist/hex:$hex');

//     final resp = await http.delete(url, headers: {'X-Api-Key': apiKey});

//     if (resp.statusCode < 200 || resp.statusCode >= 300) {
//       // some setups might also allow removing via PUT by sending updated list — fallback to full-set
//       throw Exception(
//         'NextDNS DELETE denylist failed ${resp.statusCode}: ${resp.body}',
//       );
//     }

//     // After deletion update local cache
//     final updated = await getDenylist(profileId: profileId, apiKey: apiKey);
//     await DenylistLocalRepo.instance.saveAll(updated);
//   }

//   /// Sync local repo -> remote, merging
//   static Future<void> syncLocalToRemote({
//     required String profileId,
//     required String apiKey,
//   }) async {
//     final local =
//         DenylistLocalRepo.instance.getAll().map((e) => e.toLowerCase()).toSet();
//     final remote =
//         (await getDenylist(
//           profileId: profileId,
//           apiKey: apiKey,
//         )).map((e) => e.toLowerCase()).toSet();
//     final mergedSet = <String>{};
//     mergedSet.addAll(remote);
//     mergedSet.addAll(local);
//     final mergedList = mergedSet.toList()..sort();
//     await setDenylist(
//       profileId: profileId,
//       apiKey: apiKey,
//       domains: mergedList,
//     );
//   }
// }
// lib/services/nextdns_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'denylist_local_repo.dart';

class NextDnsService {
  /// Get the current denylist from NextDNS profile as a list of domain strings.
  /// IMPORTANT: This function no longer persists into Hive. Callers decide whether
  /// to update the local cache (to avoid accidentally overwriting local data with empty remote result).
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
      if (e is String) {
        result.add(e.toLowerCase());
      } else if (e is Map && e['id'] != null) {
        result.add((e['id'] as String).toLowerCase());
      }
    }
    // NOTE: We do NOT auto-save to Hive here. Caller decides when to persist.
    return result;
  }

  /// Replace the profile denylist with the provided list of domain strings.
  /// `domains` should be a list of lowercased domain ids (no duplicates).
  static Future<void> setDenylist({
    required String profileId,
    required String apiKey,
    required List<String> domains,
  }) async {
    final normalized =
        domains
            .map((d) => d.trim().toLowerCase())
            .where((d) => d.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    // Build object-list form required by NextDNS API: [{id: "example.com", active: true}, ...]
    final mergedList =
        normalized.map((s) => {'id': s, 'active': true}).toList();

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

    // Update local cache (Hive) only after successful PATCH
    await DenylistLocalRepo.instance.saveAll(normalized);
  }

  /// Add a single domain to the profile denylist (server-side) and update local repo.
  /// This now uses setDenylist internally to send the full array.
  static Future<void> addToDenylist({
    required String profileId,
    required String apiKey,
    required String domain,
  }) async {
    final normalized = domain.trim().toLowerCase();
    if (normalized.isEmpty) throw Exception('Domain is empty');

    // Fetch remote list
    final remote = await getDenylist(profileId: profileId, apiKey: apiKey);
    final Set<String> ids = remote.map((e) => e.toLowerCase()).toSet();
    if (ids.contains(normalized)) {
      // already present -> update local repo (safe) and return
      await DenylistLocalRepo.instance.saveAll(ids.toList()..sort());
      return;
    }
    ids.add(normalized);
    final merged = ids.toList()..sort();
    await setDenylist(profileId: profileId, apiKey: apiKey, domains: merged);
  }

  /// Remove a domain from the profile denylist (server-side) and update local repo.
  /// Uses setDenylist to send the full array.
  static Future<void> removeFromDenylist({
    required String profileId,
    required String apiKey,
    required String domain,
  }) async {
    final normalized = domain.trim().toLowerCase();
    if (normalized.isEmpty) throw Exception('Domain is empty');

    final remote = await getDenylist(profileId: profileId, apiKey: apiKey);
    final ids =
        remote
            .map((e) => e.toLowerCase())
            .where((s) => s != normalized)
            .toSet();
    final merged = ids.toList()..sort();
    await setDenylist(profileId: profileId, apiKey: apiKey, domains: merged);
  }

  /// Sync local repo -> remote, merging (use if you allowed local-only edits offline)
  static Future<void> syncLocalToRemote({
    required String profileId,
    required String apiKey,
  }) async {
    final local =
        DenylistLocalRepo.instance.getAll().map((e) => e.toLowerCase()).toSet();
    final remote =
        (await getDenylist(
          profileId: profileId,
          apiKey: apiKey,
        )).map((e) => e.toLowerCase()).toSet();
    // merge sets (remote wins for duplication, just combine)
    final mergedSet = <String>{};
    mergedSet.addAll(remote);
    mergedSet.addAll(local);
    final mergedList = mergedSet.toList()..sort();
    await setDenylist(
      profileId: profileId,
      apiKey: apiKey,
      domains: mergedList,
    );
  }
}
