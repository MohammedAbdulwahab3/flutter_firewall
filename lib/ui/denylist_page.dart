import 'package:flutter/material.dart';
import '../services/nextdns_service.dart';
import '../services/denylist_local_repo.dart';

class DenylistPage extends StatefulWidget {
  final String profileId;
  final String apiKey;
  const DenylistPage({
    super.key,
    required this.profileId,
    required this.apiKey,
  });

  @override
  State<DenylistPage> createState() => _DenylistPageState();
}

class _DenylistPageState extends State<DenylistPage> {
  List<String> _items = [];
  List<String> _filtered = [];
  bool _loading = false;
  final TextEditingController _searchCtrl = TextEditingController();

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
    // load local quickly
    final local = DenylistLocalRepo.instance.getAll();
    setState(() {
      _items = local;
      _filtered = List.from(_items);
      _loading = false;
    });
    // then try remote and replace local if successful
    try {
      final remote = await NextDnsService.getDenylist(
        profileId: widget.profileId,
        apiKey: widget.apiKey,
      );
      setState(() {
        _items = remote;
        _filtered = List.from(_items);
      });
    } catch (e) {
      // ignore network errors (we already showed local)
    }
  }

  Future<void> _addDomainDialog() async {
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Add domain to denylist'),
            content: TextField(
              controller: ctrl,
              decoration: const InputDecoration(hintText: 'example.com'),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Add'),
              ),
            ],
          ),
    );
    if (res == null || res.isEmpty) return;
    await _addDomain(res);
  }

  Future<void> _addDomain(String domain) async {
    setState(() => _loading = true);
    try {
      await NextDnsService.addToDenylist(
        profileId: widget.profileId,
        apiKey: widget.apiKey,
        domain: domain,
      );
      // update local view
      final updated = await NextDnsService.getDenylist(
        profileId: widget.profileId,
        apiKey: widget.apiKey,
      );
      setState(() {
        _items = updated;
        _filtered = List.from(_items);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Added $domain')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add $domain: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _removeDomain(String domain) async {
    setState(() => _loading = true);
    try {
      await NextDnsService.removeFromDenylist(
        profileId: widget.profileId,
        apiKey: widget.apiKey,
        domain: domain,
      );
      final updated = await NextDnsService.getDenylist(
        profileId: widget.profileId,
        apiKey: widget.apiKey,
      );
      setState(() {
        _items = updated;
        _filtered = List.from(_items);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Removed $domain')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to remove $domain: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _sync() async {
    setState(() => _loading = true);
    try {
      await NextDnsService.syncLocalToRemote(
        profileId: widget.profileId,
        apiKey: widget.apiKey,
      );
      final updated = await NextDnsService.getDenylist(
        profileId: widget.profileId,
        apiKey: widget.apiKey,
      );
      setState(() {
        _items = updated;
        _filtered = List.from(_items);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Synced with NextDNS')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Denylist'),
        actions: [IconButton(onPressed: _sync, icon: const Icon(Icons.sync))],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addDomainDialog,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search denylist...',
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
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
                        return Dismissible(
                          key: Key(domain),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          confirmDismiss: (dir) async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder:
                                  (c) => AlertDialog(
                                    title: const Text('Remove from denylist?'),
                                    content: Text(
                                      'Remove $domain from denylist?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed:
                                            () => Navigator.pop(c, false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const Text('Remove'),
                                      ),
                                    ],
                                  ),
                            );
                            return ok == true;
                          },
                          onDismissed: (_) => _removeDomain(domain),
                          child: Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text(domain[0].toUpperCase()),
                              ),
                              title: Text(domain),
                              trailing: IconButton(
                                icon: const Icon(Icons.more_vert),
                                onPressed:
                                    () => showModalBottomSheet(
                                      context: context,
                                      builder:
                                          (_) => SafeArea(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ListTile(
                                                  leading: const Icon(
                                                    Icons.delete,
                                                  ),
                                                  title: const Text(
                                                    'Remove from denylist',
                                                  ),
                                                  onTap: () {
                                                    Navigator.pop(context);
                                                    _removeDomain(domain);
                                                  },
                                                ),
                                                ListTile(
                                                  leading: const Icon(
                                                    Icons.copy,
                                                  ),
                                                  title: const Text(
                                                    'Copy domain',
                                                  ),
                                                  onTap: () {
                                                    Navigator.pop(context);
                                                    // copy to clipboard if you want (Clipboard.setData)
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                    ),
                              ),
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
