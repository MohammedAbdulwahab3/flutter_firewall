// lib/ui/config_next_dns.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/nextdns_service.dart';
import '../services/denylist_local_repo.dart';

class ConfigNextDns extends StatefulWidget {
  final String profileId;
  final String apiKey;
  const ConfigNextDns({
    super.key,
    required this.profileId,
    required this.apiKey,
  });

  @override
  State<ConfigNextDns> createState() => _ConfigNextDnsState();
}

class _ConfigNextDnsState extends State<ConfigNextDns> {
  List<String> _items = [];
  List<String> _filtered = [];
  bool _loading = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _addCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLocalThenRemote();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _addCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered =
          q.isEmpty
              ? List.from(_items)
              : _items.where((s) => s.contains(q)).toList();
    });
  }

  Future<void> _loadLocalThenRemote() async {
    setState(() => _loading = true);
    try {
      final local =
          DenylistLocalRepo.instance
              .getAll()
              .map((e) => e.toLowerCase())
              .toList()
            ..sort();
      setState(() {
        _items = local;
        _filtered = List.from(_items);
      });
    } catch (_) {}
    try {
      final remote = await NextDnsService.getDenylist(
        profileId: widget.profileId,
        apiKey: widget.apiKey,
      );
      final normalized = remote.map((e) => e.toLowerCase()).toList()..sort();
      if (normalized.isNotEmpty) {
        await DenylistLocalRepo.instance.saveAll(normalized);
        setState(() {
          _items = normalized;
          _filtered = List.from(_items);
        });
      }
    } catch (e) {
      debugPrint('NextDNS fetch failed: $e');
      // keep local if remote fails
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _addDomainRemote() async {
    final raw = _addCtrl.text.trim();
    if (raw.isEmpty) return;
    setState(() => _loading = true);
    try {
      await NextDnsService.addToDenylist(
        profileId: widget.profileId,
        apiKey: widget.apiKey,
        domain: raw,
      );
      // reload remote + local
      await _loadLocalThenRemote();
      _addCtrl.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Added $raw to NextDNS denylist')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _removeDomainRemote(String domain) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text('Remove from NextDNS?'),
            content: Text('Remove $domain from NextDNS denylist?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Remove'),
              ),
            ],
          ),
    );
    if (ok != true) return;
    setState(() => _loading = true);
    try {
      await NextDnsService.removeFromDenylist(
        profileId: widget.profileId,
        apiKey: widget.apiKey,
        domain: domain,
      );
      await _loadLocalThenRemote();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Removed $domain from NextDNS')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to remove: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _syncLocalToRemote() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text('Sync local -> remote'),
            content: const Text(
              'This will merge local denylist into your NextDNS profile (remote will be updated). Proceed?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Sync'),
              ),
            ],
          ),
    );
    if (confirm != true) return;
    setState(() => _loading = true);
    try {
      await NextDnsService.syncLocalToRemote(
        profileId: widget.profileId,
        apiKey: widget.apiKey,
      );
      await _loadLocalThenRemote();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Synced local -> remote')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _refreshRemote() async {
    setState(() => _loading = true);
    try {
      final remote = await NextDnsService.getDenylist(
        profileId: widget.profileId,
        apiKey: widget.apiKey,
      );
      final normalized = remote.map((e) => e.toLowerCase()).toList()..sort();
      if (normalized.isNotEmpty) {
        await DenylistLocalRepo.instance.saveAll(normalized);
        setState(() {
          _items = normalized;
          _filtered = List.from(_items);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fetched remote denylist')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Remote denylist is empty')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Fetch failed: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NextDNS — Denylist (config)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshRemote,
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _syncLocalToRemote,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        'Profile: ${widget.profileId}',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: widget.profileId),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Profile ID copied')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addCtrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.add_link),
                      hintText: 'Add domain to NextDNS denylist (example.com)',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addDomainRemote,
                  child: const Text('Add'),
                ),
              ],
            ),
          ),

          // Padding(
          //   padding: const EdgeInsets.all(12.0),
          //   child: TextField(
          //     controller: _searchCtrl,
          //     decoration: const InputDecoration(
          //       prefixIcon: Icon(Icons.search),
          //       hintText: 'Search remote denylist...',
          //     ),
          //   ),
          // ),
          Expanded(
            child:
                _filtered.isEmpty
                    ? Center(
                      child: Text(
                        _loading ? 'Loading...' : 'Denylist is empty',
                      ),
                    )
                    : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (ctx, i) {
                        final domain = _filtered[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                domain.isNotEmpty
                                    ? domain[0].toUpperCase()
                                    : '?',
                              ),
                            ),
                            title: Text(domain),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _removeDomainRemote(domain),
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
