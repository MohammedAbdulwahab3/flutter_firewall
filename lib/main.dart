import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/dns_provider.dart'
    show DNSProvider, dnsProviders, nextDnsProvider;
import 'provider_selection_page.dart';
import 'services/nextdns_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  // MethodChannel - must match Android MainActivity channel
  static const MethodChannel _platform = MethodChannel('dns_channel');

  // protocol mapping constants - keep in sync with ProviderPicker on Android
  static const int QUERY_METHOD_UDP = 0;
  static const int QUERY_METHOD_TCP = 1;
  static const int QUERY_METHOD_HTTPS = 2; // DoH (IETF binary)
  static const int QUERY_METHOD_TLS = 3; // DoT (TLS)
  static const int QUERY_METHOD_HTTPS_JSON = 4; // DoH JSON

  DNSProvider? _selectedProvider;
  bool _isRunning = false;
  int _currentIndex = 0;

  // UI text search controller etc
  final TextEditingController _searchController = TextEditingController();

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
    final rawUpstream = provider.dns[0];
    String upstreamArg = rawUpstream;

    if (queryMethod == QUERY_METHOD_HTTPS ||
        queryMethod == QUERY_METHOD_HTTPS_JSON) {
      if (!upstreamArg.contains('/')) {
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
      print('VPN started with args: $args');
    } catch (e) {
      setState(() => _isRunning = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to start VPN: $e')));
      }
    }
  }

  /// Mapping heuristics provider -> method + port (best-effort)
  Map<String, int> _mapProviderToMethodAndPort(DNSProvider p) {
    final featuresLc = p.features.map((f) => f.toLowerCase()).toList();
    final typeLc = p.type.toLowerCase();
    final nameLc = p.name.toLowerCase();

    // Prefer encrypted if provider advertises "encrypted"
    if (featuresLc.any((f) => f.contains('encrypted'))) {
      return {'method': QUERY_METHOD_TLS, 'port': 853};
    }

    // If features or type explicitly advertise DoH/HTTPS
    if (featuresLc.any((f) => f.contains('doh') || f.contains('https')) ||
        typeLc.contains('https') ||
        nameLc.contains('doh') ||
        nameLc.contains('https')) {
      return {'method': QUERY_METHOD_HTTPS, 'port': 443};
    }

    // If features mention DoT or TLS
    if (featuresLc.any((f) => f.contains('dot') || f.contains('tls'))) {
      return {'method': QUERY_METHOD_TLS, 'port': 853};
    }

    // Specific heuristics (Mullvad is encrypted-only)
    if (nameLc.contains('mullvad')) {
      return {'method': QUERY_METHOD_TLS, 'port': 853};
    }

    // Default fallback to UDP
    return {'method': QUERY_METHOD_UDP, 'port': 53};
  }

  Future<void> _toggleVpn() async {
    if (_isRunning) {
      try {
        await _platform.invokeMethod('stopVpn');
      } catch (e) {
        // ignore, but update UI
      }
      setState(() => _isRunning = false);
      return;
    }

    // Starting VPN
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
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Block'),
              ),
            ],
          ),
    );
  }

  Future<void> _onBlockDomainTapped() async {
    final domain = await _promptForDomain();
    if (domain == null || domain.isEmpty) return;

    try {
      await NextDnsService.addToDenylist(domain);
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

    // switch to NextDNS if not already
    if (_selectedProvider?.name != nextDnsProvider.name) {
      setState(() => _selectedProvider = nextDnsProvider);
    }
    if (_isRunning) {
      // restart VPN to apply NextDNS
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

  @override
  Widget build(BuildContext context) {
    const Color kBackgroundColor = Color(0xFF1A1A2E);
    const Color kAccentColor = Colors.green;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shield Guard – IPv4 & IPv6'),
        centerTitle: true,
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
            ...[
              {'icon': Icons.public, 'label': 'Network Info', 'action': () {}},
              {
                'icon': Icons.add_to_home_screen,
                'label': 'Add Custom DNS',
                'action': () {},
              },
              {'icon': Icons.search, 'label': 'DNS Lookup', 'action': () {}},
              {'icon': Icons.settings, 'label': 'Settings', 'action': () {}},
            ].map(
              (item) => ListTile(
                leading: Icon(item['icon'] as IconData, color: Colors.white),
                title: Text(
                  item['label'] as String,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: item['action'] as VoidCallback,
              ),
            ),
            const Divider(color: Colors.grey),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Support', style: TextStyle(color: Colors.grey)),
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
