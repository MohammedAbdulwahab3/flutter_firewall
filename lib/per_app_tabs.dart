import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'manage_apps.dart';

class PerAppTabsPage extends StatefulWidget {
  const PerAppTabsPage({super.key});
  @override
  State<PerAppTabsPage> createState() => _PerAppTabsPageState();
}

class _PerAppTabsPageState extends State<PerAppTabsPage> {
  static const MethodChannel _ch = MethodChannel('dns_channel');

  bool _loading = true;
  List<String> _allowed = [];
  List<String> _blocked = [];
  List<Map<String, dynamic>> _installed = []; // label/package map
  final Map<String, Uint8List?> _iconCache = {};

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() => _loading = true);
    try {
      // get allowed/blocked
      final prefs = await _ch.invokeMethod('getPerAppPrefs');
      final allowed =
          (prefs?['allowed'] as List<dynamic>?)?.cast<String>() ?? [];
      final blocked =
          (prefs?['blocked'] as List<dynamic>?)?.cast<String>() ?? [];

      // get installed apps (labels) so we can display friendly names
      final List<dynamic> raw = await _ch.invokeMethod('listInstalledApps', {
        'includeSystem': false,
        'includeNonLaunchable': false,
      });
      final installed =
          raw
              .map((e) {
                final m = Map<String, dynamic>.from(e as Map);
                return {
                  'label': (m['label'] ?? m['package']) as String,
                  'package': m['package'] as String,
                  'isSystem': m['isSystem'] ?? false,
                  'hasLaunch': m['hasLaunch'] ?? false,
                };
              })
              .toList()
              .cast<Map<String, dynamic>>();

      // sort installed by label
      installed.sort(
        (a, b) => (a['label'] as String).toLowerCase().compareTo(
          (b['label'] as String).toLowerCase(),
        ),
      );

      setState(() {
        _allowed = allowed;
        _blocked = blocked;
        _installed = installed;
      });

      // preload icons for visible apps (allowed + blocked)
      final toLoad = <String>{};
      toLoad.addAll(_allowed);
      toLoad.addAll(_blocked);
      _queueIconLoads(toLoad.toList());
    } catch (e) {
      debugPrint('refreshAll failed: $e');
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to refresh lists: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // icon loading
  final List<String> _iconQueue = [];
  Timer? _iconTimer;
  void _queueIconLoads(List<String> pkgs) {
    for (final p in pkgs) if (!_iconCache.containsKey(p)) _iconQueue.add(p);
    if (_iconTimer?.isActive ?? false) return;
    _iconTimer = Timer.periodic(const Duration(milliseconds: 160), (t) {
      if (_iconQueue.isEmpty) {
        t.cancel();
        return;
      }
      final p = _iconQueue.removeAt(0);
      _fetchIcon(p);
    });
  }

  Future<void> _fetchIcon(String pkg) async {
    if (_iconCache.containsKey(pkg)) return;
    try {
      final String b64 = await _ch.invokeMethod('getAppIcon', {'package': pkg});
      if (b64.isEmpty) {
        setState(() => _iconCache[pkg] = null);
        return;
      }
      final bytes = base64Decode(b64);
      setState(() => _iconCache[pkg] = bytes);
    } catch (e) {
      setState(() => _iconCache[pkg] = null);
    }
  }

  Map<String, dynamic>? _findInstalledMeta(String pkg) {
    return _installed.firstWhere(
      (m) => m['package'] == pkg,
      orElse: () => {'label': pkg, 'package': pkg},
    );
  }

  Widget _buildList(List<String> pkgs, Color accent) {
    if (pkgs.isEmpty) {
      return Center(
        child: Text('No apps here', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      itemCount: pkgs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final pkg = pkgs[i];
        final meta = _findInstalledMeta(pkg)!;
        final label = meta['label'] as String;
        final icon = _iconCache[pkg];
        final leading =
            icon != null
                ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(
                    icon,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  ),
                )
                : Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.grey.shade100,
                  ),
                  child: Icon(Icons.apps, color: Colors.grey[600]),
                );

        return ListTile(
          leading: leading,
          title: Text(label),
          subtitle: Text(pkg, style: TextStyle(fontSize: 12)),
          trailing: Icon(Icons.circle, color: accent, size: 12),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('App Filtering'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Allowed (${_allowed.length})'),
              Tab(text: 'Blocked (${_blocked.length})'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.manage_accounts),
              tooltip: 'Manage apps',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ManageAppsPage()),
                );
                await _refreshAll();
              },
            ),

            IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshAll),
          ],
        ),
        body:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                  children: [
                    _buildList(_allowed, Colors.green),
                    _buildList(_blocked, Colors.red),
                  ],
                ),
      ),
    );
  }
}
