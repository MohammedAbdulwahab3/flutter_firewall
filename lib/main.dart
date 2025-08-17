// lib/main.dart
import 'package:dns_changer/blocklist_page.dart';
import 'package:dns_changer/home_page.dart';
import 'package:dns_changer/per_app_tabs.dart';
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
  await DenylistLocalRepo.instance.init(); // initialize Hive box before runApp
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SecureNet',
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
