// // lib/manage_apps.dart
// import 'dart:convert';
// import 'dart:typed_data';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';

// class ManageAppsPage extends StatefulWidget {
//   const ManageAppsPage({super.key});
//   @override
//   State<ManageAppsPage> createState() => _ManageAppsPageState();
// }

// class _ManageAppsPageState extends State<ManageAppsPage> {
//   static const MethodChannel _ch = MethodChannel('dns_channel');

//   List<Map<String, dynamic>> _apps = [];
//   final Set<String> _selected = {};
//   final Map<String, Uint8List?> _icons = {};
//   bool _loading = true;
//   String _query = '';
//   bool _includeSystem = false;

//   @override
//   void initState() {
//     super.initState();
//     _loadApps();
//   }

//   Future<void> _loadApps() async {
//     setState(() {
//       _loading = true;
//       _apps = [];
//       _selected.clear();
//       _icons.clear();
//     });
//     try {
//       final List<dynamic> res = await _ch.invokeMethod('listInstalledApps', {
//         'includeSystem': _includeSystem,
//         'includeNonLaunchable': false,
//       });
//       final apps =
//           res.map((e) {
//             final m = Map<String, dynamic>.from(e as Map);
//             return {
//               'label': (m['label'] ?? m['package']) as String,
//               'package': m['package'] as String,
//               'isSystem': m['isSystem'] ?? false,
//               'hasLaunch': m['hasLaunch'] ?? false,
//             };
//           }).toList();
//       apps.sort(
//         (a, b) => (a['label'] as String).toLowerCase().compareTo(
//           (b['label'] as String).toLowerCase(),
//         ),
//       );
//       setState(() => _apps = apps.cast<Map<String, dynamic>>());
//       // prefetch first icons
//       for (
//         var i = 0;
//         i < (_apps.length & _apps.length < 40 ? _apps.length : 40);
//         i++
//       ) {
//         _fetchIcon(_apps[i]['package'] as String);
//       }
//     } catch (e) {
//       if (mounted)
//         ScaffoldMessenger.of(
//           context,
//         ).showSnackBar(SnackBar(content: Text('Failed: $e')));
//     } finally {
//       if (mounted) setState(() => _loading = false);
//     }
//   }

//   Future<void> _fetchIcon(String pkg) async {
//     if (_icons.containsKey(pkg)) return;
//     try {
//       final String b64 = await _ch.invokeMethod('getAppIcon', {'package': pkg});
//       if (b64.isEmpty) {
//         setState(() => _icons[pkg] = null);
//         return;
//       }
//       setState(() => _icons[pkg] = base64Decode(b64));
//     } catch (_) {
//       setState(() => _icons[pkg] = null);
//     }
//   }

//   void _toggle(String pkg) {
//     setState(() {
//       if (_selected.contains(pkg))
//         _selected.remove(pkg);
//       else
//         _selected.add(pkg);
//     });
//   }

//   Future<void> _applyAdd(String mode) async {
//     final pkgs = _selected.toList();
//     if (pkgs.isEmpty) {
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(const SnackBar(content: Text('No apps selected')));
//       return;
//     }
//     try {
//       // IMPORTANT: operation "add" to merge with existing sets
//       await _ch.invokeMethod('updatePerAppFilter', {
//         'mode': mode,
//         'packages': pkgs,
//         'operation': 'add',
//       });
//       if (mounted)
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Added ${pkgs.length} to $mode')),
//         );
//       Navigator.of(context).pop(); // go back to tabs which will refresh
//     } catch (e) {
//       if (mounted)
//         ScaffoldMessenger.of(
//           context,
//         ).showSnackBar(SnackBar(content: Text('Failed: $e')));
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final filtered =
//         _apps.where((a) {
//           if (_query.isEmpty) return true;
//           final q = _query.toLowerCase();
//           final lab = (a['label'] as String).toLowerCase();
//           final pkg = (a['package'] as String).toLowerCase();
//           return lab.contains(q) || pkg.contains(q);
//         }).toList();

//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Manage apps'),
//         actions: [
//           IconButton(icon: const Icon(Icons.refresh), onPressed: _loadApps),
//         ],
//       ),
//       body:
//           _loading
//               ? const Center(child: CircularProgressIndicator())
//               : Column(
//                 children: [
//                   Padding(
//                     padding: const EdgeInsets.all(8.0),
//                     child: Row(
//                       children: [
//                         Expanded(
//                           child: TextField(
//                             decoration: const InputDecoration(
//                               prefixIcon: Icon(Icons.search),
//                               hintText: 'Search',
//                             ),
//                             onChanged: (v) => setState(() => _query = v),
//                           ),
//                         ),
//                         const SizedBox(width: 8),
//                         FilterChip(
//                           label: const Text('Include system'),
//                           selected: _includeSystem,
//                           onSelected:
//                               (v) => setState(() {
//                                 _includeSystem = v;
//                                 _loadApps();
//                               }),
//                         ),
//                       ],
//                     ),
//                   ),
//                   Padding(
//                     padding: const EdgeInsets.symmetric(horizontal: 12.0),
//                     child: Row(
//                       children: [
//                         Expanded(
//                           child: ElevatedButton.icon(
//                             icon: const Icon(Icons.check),
//                             label: const Text('Add to Allowed'),
//                             onPressed: () => _applyAdd('allow'),
//                           ),
//                         ),
//                         const SizedBox(width: 8),
//                         Expanded(
//                           child: ElevatedButton.icon(
//                             icon: const Icon(Icons.block),
//                             label: const Text('Add to Blocked'),
//                             onPressed: () => _applyAdd('block'),
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                   const SizedBox(height: 8),
//                   Expanded(
//                     child:
//                         filtered.isEmpty
//                             ? const Center(child: Text('No apps found'))
//                             : ListView.builder(
//                               itemCount: filtered.length,
//                               itemBuilder: (ctx, i) {
//                                 final a = filtered[i];
//                                 final pkg = a['package'] as String;
//                                 if (!_icons.containsKey(pkg)) _fetchIcon(pkg);
//                                 final icon = _icons[pkg];
//                                 final leading =
//                                     icon != null
//                                         ? Image.memory(
//                                           icon,
//                                           width: 42,
//                                           height: 42,
//                                         )
//                                         : Container(
//                                           width: 42,
//                                           height: 42,
//                                           color: Colors.grey[200],
//                                           child: const Icon(Icons.apps),
//                                         );
//                                 return ListTile(
//                                   leading: leading,
//                                   title: Text(a['label'] as String),
//                                   subtitle: Text(
//                                     pkg,
//                                     style: const TextStyle(fontSize: 12),
//                                   ),
//                                   trailing: Checkbox(
//                                     value: _selected.contains(pkg),
//                                     onChanged: (_) => _toggle(pkg),
//                                   ),
//                                   onTap: () => _toggle(pkg),
//                                 );
//                               },
//                             ),
//                   ),
//                 ],
//               ),
//     );
//   }
// }

// lib/manage_apps.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ManageAppsPage extends StatefulWidget {
  const ManageAppsPage({super.key});
  @override
  State<ManageAppsPage> createState() => _ManageAppsPageState();
}

class _ManageAppsPageState extends State<ManageAppsPage> {
  static const MethodChannel _ch = MethodChannel('dns_channel');

  List<Map<String, dynamic>> _apps = [];
  final Set<String> _selected = {};
  final Map<String, Uint8List?> _icons = {};
  bool _loading = true;
  String _query = '';
  bool _includeSystem = false;

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    setState(() {
      _loading = true;
      _apps = [];
      _selected.clear();
      _icons.clear();
    });
    try {
      final List<dynamic> res = await _ch.invokeMethod('listInstalledApps', {
        'includeSystem': _includeSystem,
        'includeNonLaunchable': false,
      });
      final apps =
          res.map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return {
              'label': (m['label'] ?? m['package']) as String,
              'package': m['package'] as String,
              'isSystem': m['isSystem'] ?? false,
              'hasLaunch': m['hasLaunch'] ?? false,
            };
          }).toList();
      apps.sort(
        (a, b) => (a['label'] as String).toLowerCase().compareTo(
          (b['label'] as String).toLowerCase(),
        ),
      );
      setState(() => _apps = apps.cast<Map<String, dynamic>>());
      // prefetch first icons
      for (
        var i = 0;
        i < (_apps.length & _apps.length < 40 ? _apps.length : 40);
        i++
      ) {
        _fetchIcon(_apps[i]['package'] as String);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchIcon(String pkg) async {
    if (_icons.containsKey(pkg)) return;
    try {
      final String b64 = await _ch.invokeMethod('getAppIcon', {'package': pkg});
      if (b64.isEmpty) {
        setState(() => _icons[pkg] = null);
        return;
      }
      setState(() => _icons[pkg] = base64Decode(b64));
    } catch (_) {
      setState(() => _icons[pkg] = null);
    }
  }

  void _toggle(String pkg) {
    setState(() {
      if (_selected.contains(pkg))
        _selected.remove(pkg);
      else
        _selected.add(pkg);
    });
  }

  Future<void> _applyAdd(String mode) async {
    final pkgs = _selected.toList();
    if (pkgs.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No apps selected')));
      return;
    }
    try {
      // IMPORTANT: operation "add" to merge with existing sets
      await _ch.invokeMethod('updatePerAppFilter', {
        'mode': mode,
        'packages': pkgs,
        'operation': 'add',
      });
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${pkgs.length} to $mode')),
        );
      Navigator.of(context).pop(); // go back to tabs which will refresh
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered =
        _apps.where((a) {
          if (_query.isEmpty) return true;
          final q = _query.toLowerCase();
          final lab = (a['label'] as String).toLowerCase();
          final pkg = (a['package'] as String).toLowerCase();
          return lab.contains(q) || pkg.contains(q);
        }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage apps'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadApps),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Search',
                            ),
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Include system'),
                          selected: _includeSystem,
                          onSelected:
                              (v) => setState(() {
                                _includeSystem = v;
                                _loadApps();
                              }),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.check),
                            label: const Text('Add to Allowed'),
                            onPressed: () => _applyAdd('allow'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.block),
                            label: const Text('Add to Blocked'),
                            onPressed: () => _applyAdd('block'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child:
                        filtered.isEmpty
                            ? const Center(child: Text('No apps found'))
                            : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                final a = filtered[i];
                                final pkg = a['package'] as String;
                                if (!_icons.containsKey(pkg)) _fetchIcon(pkg);
                                final icon = _icons[pkg];
                                final leading =
                                    icon != null
                                        ? Image.memory(
                                          icon,
                                          width: 42,
                                          height: 42,
                                        )
                                        : Container(
                                          width: 42,
                                          height: 42,
                                          color: Colors.grey[200],
                                          child: const Icon(Icons.apps),
                                        );
                                return ListTile(
                                  leading: leading,
                                  title: Text(a['label'] as String),
                                  subtitle: Text(
                                    pkg,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Checkbox(
                                    value: _selected.contains(pkg),
                                    onChanged: (_) => _toggle(pkg),
                                  ),
                                  onTap: () => _toggle(pkg),
                                );
                              },
                            ),
                  ),
                ],
              ),
    );
  }
}
