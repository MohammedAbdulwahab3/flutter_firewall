class DNSProvider {
  final String name;
  final List<String> dns;
  final List<String> features;
  final String description;
  final String type;
  final List<String>? ipv6;
  final String? doh; // optional DoH host/path (e.g. 'dns.nextdns.io/46bded')

  const DNSProvider({
    required this.name,
    required this.dns,
    required this.features,
    this.description = '',
    this.type = 'Public',
    this.ipv6,
    this.doh,
  });
}

/// NextDNS profile (example: 46bded)
const DNSProvider nextDnsProvider = DNSProvider(
  name: 'NextDNS',
  type: 'Plain DNS Anycast',
  dns: [
    '45.90.28.81', // linked IP #1
    '45.90.30.81', // linked IP #2
  ],
  ipv6: [
    '2a07:a8c0::46:bded', // IPv6 Anycast #1
    '2a07:a8c1::46:bded', // IPv6 Anycast #2
  ],
  features: ['Custom Blocklists', 'Analytics'],
  description:
      'NextDNS profile 46bded over Anycast. Use linked IPs for plain DNS; prefer the profile-specific DoH/DoT endpoints for profile settings to apply.',
  // canonical DoH endpoint for the profile. If the user configures another profileId at runtime, the app will prefer that.
  doh: 'dns.nextdns.io/46bded',
);

const List<DNSProvider> dnsProviders = [
  DNSProvider(
    name: 'Google DNS',
    dns: ['8.8.8.8', '8.8.4.4'],
    ipv6: ['2001:4860:4860::8888', '2001:4860:4860::8844'],
    features: ['High Reliability', 'Global Coverage'],
    description:
        'Google Public DNS aims to make the Internet faster and more secure. It does not filter or block domains, and leverages Google’s global network.',
    doh: null,
  ),
  DNSProvider(
    name: 'Cloudflare DNS',
    dns: ['1.1.1.1', '1.0.0.1'],
    ipv6: ['2606:4700:4700::1111', '2606:4700:4700::1001'],
    features: ['Ultra-fast', 'Privacy-focused', 'DoH/DoT'],
    description:
        'Operated by Cloudflare and APNIC, 1.1.1.1 is one of the fastest public DNS resolvers. Supports DNS-over-HTTPS and TLS, with a strict no-logs policy.',
    doh: null,
  ),
  DNSProvider(
    name: 'OpenDNS FamilyShield',
    dns: ['208.67.222.123', '208.67.220.123'],
    features: ['Preconfigured Adult Blocking', 'Phishing Protection'],
    description:
        'OpenDNS FamilyShield is a free preset that blocks adult content and phishing sites. No registration required—simply set these IPs to enable.',
    doh: null,
  ),
  DNSProvider(
    name: 'OpenDNS Home',
    dns: ['208.67.222.222', '208.67.220.220'],
    features: ['Customizable Filtering', 'Stats Dashboard'],
    description:
        'OpenDNS Home offers a web-based dashboard where you can create custom filters, view usage stats, and set security policies for your network.',
    doh: null,
  ),
  // Keep NextDNS in the list (same as nextDnsProvider)
  DNSProvider(
    name: 'NextDNS',
    type: 'Plain DNS Anycast',
    dns: ['45.90.28.81', '45.90.30.81'],
    ipv6: ['2a07:a8c0::46:bded', '2a07:a8c1::46:bded'],
    features: ['Custom Blocklists', 'Analytics'],
    description:
        'NextDNS is a fully-customizable DNS firewall. Configure your blocklists via their web dashboard or API, then route all queries over these anycast servers.',
    doh: 'dns.nextdns.io/46bded',
  ),
  DNSProvider(
    name: 'Quad9',
    dns: ['9.9.9.9', '149.112.112.112'],
    ipv6: ['2620:fe::fe', '2620:fe::9'],
    features: ['Malware & Phishing Block', 'DNSSEC', 'No Logs'],
    description:
        'Quad9 routes your DNS queries through a secure network of servers around the world. Blocks known malicious domains using threat intelligence feeds and enforces DNSSEC.',
    doh: null,
  ),
  DNSProvider(
    name: 'AdGuard DNS',
    dns: ['94.140.14.14', '94.140.15.15'],
    ipv6: ['2a10:50c0::ad1:ff', '2a10:50c0::ad2:ff'],
    features: ['Ad & Tracker Blocking', 'Malware Filter'],
    description:
        'AdGuard DNS blocks ads, trackers, and malicious websites at the DNS level. No software installation required, just set the DNS servers in your device.',
    doh: null,
  ),
  DNSProvider(
    name: 'CleanBrowsing Family Filter',
    dns: ['185.228.168.168', '185.228.169.168'],
    features: ['Adult Content Block', 'Phishing Protection'],
    description:
        'CleanBrowsing’s Family Filter blocks adult content, raises SafeSearch flags, and prevents access to malicious sites. Designed for home and family use.',
    doh: null,
  ),
  DNSProvider(
    name: 'Control D – No Filter',
    dns: ['76.76.2.0', '76.76.10.0'],
    features: ['No Filtering', 'Fast Resolver'],
    description:
        'Control D’s “No Filter” preset provides a privacy-focused resolver without blocking. Ideal for testing or custom profile setups.',
    doh: null,
  ),
  DNSProvider(
    name: 'Control D – Ad Block',
    dns: ['76.76.2.1', '76.76.10.1'],
    features: ['Ads & Trackers Block'],
    description:
        'Blocks domains known to serve ads and tracking scripts. Useful for cleaner browsing without installing browser extensions.',
    doh: null,
  ),
  DNSProvider(
    name: 'Control D – Social Media Block',
    dns: ['76.76.2.2', '76.76.10.2'],
    features: ['Social Media Domains Block'],
    description:
        'Filters out popular social media platforms (e.g., Facebook, TikTok) to help enforce digital well-being or workplace focus.',
    doh: null,
  ),
  DNSProvider(
    name: 'Control D – Porn Block',
    dns: ['76.76.2.3', '76.76.10.3'],
    features: ['Adult Content Block'],
    description:
        'Blocks access to adult sites. Great for parental controls or public/shared devices.',
    doh: null,
  ),
  DNSProvider(
    name: 'Comodo Secure DNS',
    dns: ['8.26.56.26', '8.20.247.20'],
    features: ['Malware & Phishing Block'],
    description:
        'Comodo Secure DNS provides real-time protection against malicious and phishing sites. No registration required, simply configure your DNS to these servers.',
    doh: null,
  ),
  DNSProvider(
    name: 'Yandex DNS (Family Shield)',
    dns: ['77.88.8.7', '77.88.8.3'],
    features: ['Family Shield', 'Adult Content Filter'],
    description:
        'Yandex Family Shield blocks adult content automatically. Also offers Basic and Safe tiers for performance or malware protection.',
    doh: null,
  ),
  DNSProvider(
    name: 'Alternate DNS',
    dns: ['76.76.19.19', '76.223.122.150'],
    features: ['Ad Blocking'],
    description:
        'Alternate DNS blocks ads and malicious domains. A simple, no-frills ad blocker at the DNS level.',
    doh: null,
  ),
  DNSProvider(
    name: 'Neustar UltraDNS',
    dns: ['156.154.70.1', '156.154.71.1'],
    features: ['Enterprise-Grade Filtering'],
    description:
        'UltraDNS from Neustar delivers business-grade DNS security, including phishing, malware, and botnet protection with high availability.',
    doh: null,
  ),
  DNSProvider(
    name: 'Mullvad DNS',
    dns: ['193.138.218.74', '185.213.26.187'],
    features: ['Privacy-Focused', 'Encrypted Only'],
    description:
        'Mullvad DNS only supports DNS-over-HTTPS/TLS, guaranteeing encrypted queries and strict no-logs policy for maximum privacy.',
    doh: null,
  ),
];
