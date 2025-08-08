// // lib/services/nextdns_service.dart

// import 'dart:convert';
// import 'package:http/http.dart' as http;

// const _profileId = 'd4c36a';
// const _apiKey = 'YOUR_NEXTDNS_API_KEY';

// class NextDnsService {
//   /// Throws on any non-204 response, with status+body.
//   static Future<void> addToDenylist(String domain) async {
//     final uri = Uri.https('api.nextdns.io', '/profiles/$_profileId/denylist');
//     final resp = await http.post(
//       uri,
//       headers: {
//         'Authorization': 'Bearer $_apiKey',
//         'Content-Type': 'application/json',
//       },
//       body: jsonEncode({'domain': domain}),
//     );

//     if (resp.statusCode != 204) {
//       throw Exception(
//         'API ${resp.statusCode}: ${resp.body.isEmpty ? '<no body>' : resp.body}',
//       );
//     }
//   }
// // }

// import 'dart:convert';
// import 'package:http/http.dart' as http;

// class NextDnsService {
//   static const String _profileId =
//       '46bded'; // Replace with your actual profile ID
//   static const String _apiKey =
//       '5f83bcd82d612b9f0694be53eedb8e84aec7e9dd'; // Replace with your actual API Key
//   // Base URL for NextDNS API
//   static const String _baseUrl = 'https://api.nextdns.io';

//   /// Adds a domain to the denylist
//   static Future<void> addToDenylist(String domain) async {
//     final url = Uri.parse('$_baseUrl/profiles/$_profileId/');

//     final denylist =
//         domains.map((domain) => {"id": domain, "active": true}).toList();

//     final body = jsonEncode({"denylist": denylist});

//     final response = await http.post(
//       url,
//       headers: {'Content-Type': 'application/json', 'X-API-Key': _apiKey},
//       body: body,
//     );

//     if (response.statusCode == 200 || response.statusCode == 201) {
//       // Successfully added
//       print('✅ Domain added: $domain');
//     } else {
//       // Something went wrong
//       final error = jsonDecode(response.body);
//       throw Exception('Failed to add domain: $error');
//     }
//   }
// }

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/http.dart' as https;

class NextDnsService {
  static const String _profileId =
      '46bded'; // Replace with your actual profile ID
  static const String _apiKey =
      '5f83bcd82d612b9f0694be53eedb8e84aec7e9dd'; // Replace with your actual API Key
  static const String _baseUrl = 'https://api.nextdns.io';

  /// Adds a single domain to the denylist
  static Future<void> addToDenylist(String domain) async {
    final url = Uri.parse('$_baseUrl/profiles/$_profileId/');

    // Build the denylist with the single domain
    final denylist = [
      {"id": domain, "active": true},
    ];

    final body = jsonEncode({"denylist": denylist});

    final response = await http.patch(
      url,
      headers: {'Content-Type': 'application/json', 'X-API-Key': _apiKey},
      body: body,
    );

    if (response.statusCode == 204 || response.statusCode == 201) {
      print('✅ Domain added: $domain');
    } else {
      final error = jsonDecode(response.body);
      throw Exception('❌ Failed to add domain: $error');
      print(error);
    }
  }
}
