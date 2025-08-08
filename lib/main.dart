import 'package:dns_changer/services/denylist_local_repo.dart';
import 'package:dns_changer/services/nextdns_service.dart';
import 'package:dns_changer/ui/denylist_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/dns_provider.dart'
    show DNSProvider, dnsProviders, nextDnsProvider;
import 'provider_selection_page.dart';
import 'package:hive_flutter/hive_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await DenylistLocalRepo.instance.init(); // below class
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shield Guard',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1A2E),
          elevation: 0,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const MethodChannel _platform = MethodChannel('dns_channel');

  static const int QUERY_METHOD_UDP = 0;
  static const int QUERY_METHOD_TCP = 1;
  static const int QUERY_METHOD_HTTPS = 2; // DoH (IETF binary)
  static const int QUERY_METHOD_TLS = 3; // DoT (TLS)
  static const int QUERY_METHOD_HTTPS_JSON = 4; // DoH JSON

  DNSProvider? _selectedProvider;
  bool _isRunning = false;
  int _currentIndex = 0;

  final TextEditingController _searchController = TextEditingController();

  // runtime NextDNS creds (kept in-memory only — not persisted)
  String? _nextDnsProfileId = '46bded';
  String? _nextDnsApiKey = '5f83bcd82d612b9f0694be53eedb8e84aec7e9dd';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _startVpnForProvider({
    required DNSProvider provider,
    required int queryMethod,
    required int port1,
    int? port2,
  }) async {
    String upstreamArg = provider.dns.isNotEmpty ? provider.dns[0] : '';

    // If provider is NextDNS and a profileId is configured, prefer profile-scoped DoH.
    if (provider.name.toLowerCase().contains('nextdns') &&
        _nextDnsProfileId != null &&
        _nextDnsProfileId!.isNotEmpty) {
      // Use official DoH endpoint from the profile: dns.nextdns.io/PROFILEID
      upstreamArg = 'dns.nextdns.io/${_nextDnsProfileId!.trim()}';
      queryMethod = QUERY_METHOD_HTTPS;
    } else if (provider.doh != null && provider.doh!.isNotEmpty) {
      // If provider has an explicit doh field (e.g. dns.nextdns.io/46bded), prefer it
      upstreamArg = provider.doh!;
      queryMethod = QUERY_METHOD_HTTPS;
    } else {
      if ((queryMethod == QUERY_METHOD_HTTPS ||
              queryMethod == QUERY_METHOD_HTTPS_JSON) &&
          !upstreamArg.contains('/')) {
        upstreamArg = '$upstreamArg/dns-query';
      }
    }

    final args = <String, Object>{
      'dns1': upstreamArg,
      if (provider.dns.length > 1) 'dns2': provider.dns[1],
      'queryMethod': queryMethod,
      'port1': port1,
      'port2': port2 ?? port1,
    };

    try {
      await _platform.invokeMethod('startVpn', args);
      setState(() => _isRunning = true);
      debugPrint('VPN started with args: $args');
    } catch (e) {
      setState(() => _isRunning = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start VPN: $e')));
      }
    }
  }

  Map<String, int> _mapProviderToMethodAndPort(DNSProvider p) {
    final featuresLc = p.features.map((f) => f.toLowerCase()).toList();
    final typeLc = p.type.toLowerCase();
    final nameLc = p.name.toLowerCase();

    if (featuresLc.any((f) => f.contains('encrypted'))) {
      return {'method': QUERY_METHOD_TLS, 'port': 853};
    }

    if (featuresLc.any((f) => f.contains('doh') || f.contains('https')) ||
        typeLc.contains('https') ||
        nameLc.contains('doh') ||
        nameLc.contains('https')) {
      return {'method': QUERY_METHOD_HTTPS, 'port': 443};
    }

    if (featuresLc.any((f) => f.contains('dot') || f.contains('tls'))) {
      return {'method': QUERY_METHOD_TLS, 'port': 853};
    }

    if (nameLc.contains('mullvad')) {
      return {'method': QUERY_METHOD_TLS, 'port': 853};
    }

    return {'method': QUERY_METHOD_UDP, 'port': 53};
  }

  Future<void> _toggleVpn() async {
    if (_isRunning) {
      try {
        await _platform.invokeMethod('stopVpn');
      } catch (e) {}
      setState(() => _isRunning = false);
      return;
    }

    if (_selectedProvider == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a DNS provider first')),
      );
      return;
    }

    final mapping = _mapProviderToMethodAndPort(_selectedProvider!);
    final method = mapping['method']!;
    final port = mapping['port']!;

    await _startVpnForProvider(
      provider: _selectedProvider!,
      queryMethod: method,
      port1: port,
      port2: port,
    );
  }

  Future<String?> _promptForDomain() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Block a domain'),
            content: TextField(
              controller: ctrl,
              decoration: const InputDecoration(hintText: 'e.g. facebook.com'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx, ctrl.text.trim());
                },
                child: const Text('Block'),
              ),
            ],
          ),
    );
  }

  Future<void> _onBlockDomainTapped() async {
    final domain = await _promptForDomain();
    if (domain == null || domain.isEmpty) return;

    if (_nextDnsProfileId == null ||
        _nextDnsProfileId!.isEmpty ||
        _nextDnsApiKey == null ||
        _nextDnsApiKey!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please configure NextDNS Profile ID and API Key in settings first',
            ),
          ),
        );
      }
      return;
    }

    try {
      await NextDnsService.addToDenylist(
        profileId: _nextDnsProfileId!.trim(),
        apiKey: _nextDnsApiKey!.trim(),
        domain: domain,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $domain to NextDNS denylist')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to add $domain: $e')));
      }
      return;
    }

    // ensure profile is selected and restart VPN to apply immediately (your existing logic)
    if (_selectedProvider?.name != nextDnsProvider.name) {
      setState(() => _selectedProvider = nextDnsProvider);
    }
    if (_isRunning) {
      try {
        await _platform.invokeMethod('stopVpn');
      } catch (_) {}
      final mapping = _mapProviderToMethodAndPort(nextDnsProvider);
      await _startVpnForProvider(
        provider: nextDnsProvider,
        queryMethod: mapping['method']!,
        port1: mapping['port']!,
        port2: mapping['port']!,
      );
    }
  }

  Future<void> _goToSelection() async {
    final result = await Navigator.push<DNSProvider>(
      context,
      MaterialPageRoute(builder: (_) => const ProviderSelectionPage()),
    );
    if (result != null) {
      final wasRunning = _isRunning;
      if (wasRunning) {
        try {
          await _platform.invokeMethod('stopVpn');
        } catch (_) {}
      }

      setState(() => _selectedProvider = result);

      if (wasRunning) {
        final mapping = _mapProviderToMethodAndPort(_selectedProvider!);
        await _startVpnForProvider(
          provider: _selectedProvider!,
          queryMethod: mapping['method']!,
          port1: mapping['port']!,
          port2: mapping['port']!,
        );
      }
    }
  }

  Future<void> _showNextDnsConfigDialog() async {
    final pidCtrl = TextEditingController(text: _nextDnsProfileId ?? '');
    final keyCtrl = TextEditingController(text: _nextDnsApiKey ?? '');
    final res = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('NextDNS Configuration'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: pidCtrl,
                  decoration: const InputDecoration(labelText: 'Profile ID'),
                ),
                TextField(
                  controller: keyCtrl,
                  decoration: const InputDecoration(labelText: 'API Key'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Find profile id and API key at https://my.nextdns.io (Endpoints / Account)',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save'),
              ),
            ],
          ),
    );

    if (res == true) {
      setState(() {
        _nextDnsProfileId = pidCtrl.text.trim();
        _nextDnsApiKey = keyCtrl.text.trim();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('NextDNS credentials set (in-memory)')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color kBackgroundColor = Color(0xFF1A1A2E);
    const Color kAccentColor = Colors.green;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shield Guard – IPv4 & IPv6'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'NextDNS settings',
            icon: const Icon(Icons.settings),
            onPressed: _showNextDnsConfigDialog,
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF16213E)),
              child: Text(
                'Shield Guard',
                style: TextStyle(color: Colors.white, fontSize: 32),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.white),
              title: const Text(
                'Block a Site',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _onBlockDomainTapped();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud, color: Colors.white),
              title: const Text(
                'NextDNS Config',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                _nextDnsProfileId ?? 'Not configured',
                style: const TextStyle(color: Colors.white70),
              ),
              onTap: () {
                Navigator.pop(context);
                _showNextDnsConfigDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.filter_list_alt, color: Colors.white),
              title: const Text(
                'NextDNS denaylist',
                style: TextStyle(color: Colors.red),
              ),

              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => DenylistPage(
                          profileId: _nextDnsProfileId!,
                          apiKey: _nextDnsApiKey!,
                        ),
                  ),
                );
              },
            ),
            const Divider(color: Colors.grey),
            ...[
              {'icon': Icons.share, 'label': 'Share this app'},
              {'icon': Icons.feedback, 'label': 'Send Feedback'},
              {'icon': Icons.thumb_up, 'label': 'Rate us'},
              {'icon': Icons.info, 'label': 'About us'},
            ].map(
              (item) => ListTile(
                leading: Icon(item['icon'] as IconData, color: Colors.white),
                title: Text(
                  item['label'] as String,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {},
              ),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            GestureDetector(
              onTap: _goToSelection,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _selectedProvider == null
                      ? 'Select server'
                      : 'Selected: ${_selectedProvider!.name}',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _toggleVpn,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.green, width: 4),
                ),
                child: Center(
                  child: Icon(
                    _isRunning ? Icons.power_off : Icons.power_settings_new,
                    size: 60,
                    color: Colors.green,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isRunning ? 'Stop' : 'Start',
              style: const TextStyle(fontSize: 18, color: Colors.green),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isRunning ? Icons.check_circle : Icons.cancel,
                  color: _isRunning ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  'Status: ${_isRunning ? 'Connected' : 'Disconnected'}',
                  style: TextStyle(
                    color: _isRunning ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.speed), label: 'Speed'),
          BottomNavigationBarItem(icon: Icon(Icons.apps), label: 'Apps'),
        ],
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}
