package com.example.dns_changer

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import android.util.Log
import android.util.Patterns
import com.example.dns_changer.provider.Provider
import com.example.dns_changer.provider.ProviderPicker
import org.minidns.dnsmessage.DnsMessage
import org.pcap4j.packet.IpPacket
import java.net.DatagramSocket
import java.util.concurrent.atomic.AtomicBoolean
import android.net.ConnectivityManager
import android.os.Handler
import android.os.Looper

class DnsVpnService : VpnService(), Runnable {
    companion object {
        const val ACTION_START = "com.example.dns_changer.START"
        const val ACTION_STOP  = "com.example.dns_changer.STOP"
        const val EXTRA_ALLOWED_APPS = "allowedApps"
        const val EXTRA_BLOCKED_APPS = "blockedApps"
        private const val TAG = "DnsVpnService"
    }

    // ---- Defaults pointed to your Go server (change if needed) ----
    var upstream1: String = "10.128.211.158"                              // numeric IP for UDP/TCP
    var upstream2: String = "https://10.128.211.158:8080/dns-query"       // DoH endpoint fallback
    var port1 = 8053
    var port2 = 8080
    var queryMethod = ProviderPicker.UDP   // default to UDP provider (works without TLS)
    // ---------------------------------------------------------------

    private var descriptor: ParcelFileDescriptor? = null
    private var thread: Thread? = null
    private var provider: Provider? = null
    private val running = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    @Volatile
    var useLocalBlocklist: Boolean = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureForeground()

        when (intent?.action) {
            ACTION_START -> {
                intent.getStringExtra("dns1")?.let { upstream1 = it }
                intent.getStringExtra("dns2")?.let { upstream2 = it }

                try { val qm = intent.getIntExtra("queryMethod", queryMethod); queryMethod = qm } catch (_: Exception) {}
                try {
                    val p1 = intent.getIntExtra("port1", port1)
                    val p2 = intent.getIntExtra("port2", port2)
                    port1 = p1; port2 = p2
                } catch (_: Exception) {}

                try {
                    useLocalBlocklist = intent.getBooleanExtra("useLocalBlocklist", false)
                } catch (_: Exception) {}

                Log.i(TAG, "START intent: upstream1=$upstream1 port1=$port1 queryMethod=$queryMethod useLocalBlock=$useLocalBlocklist")
                startVpn(intent)
            }
            ACTION_STOP -> stopVpn()
            else -> {
                Log.i(TAG, "onStartCommand unknown action: ${intent?.action}")
            }
        }
        return START_STICKY
    }

    private fun ensureForeground() {
        try {
            val channelId = "dns_vpn_service"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = getSystemService(NotificationManager::class.java)
                val chan = NotificationChannel(channelId, "Shield Guard VPN", NotificationManager.IMPORTANCE_LOW)
                nm.createNotificationChannel(chan)
            }
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, channelId)
            } else {
                Notification.Builder(this)
            }
            val notification = builder
                .setContentTitle("Shield Guard")
                .setContentText("VPN running")
                .setSmallIcon(android.R.drawable.sym_def_app_icon)
                .setOngoing(true)
                .build()
            startForeground(1, notification)
        } catch (ex: Exception) {
            Log.w(TAG, "startForeground failed: ${ex.message}")
        }
    }

    private fun isIpAddress(addr: String?): Boolean {
        if (addr == null) return false
        return Patterns.IP_ADDRESS.matcher(addr).matches()
    }

    private fun startVpn(startIntent: Intent?) {
        if (running.get()) {
            Log.i(TAG, "VPN already running")
            return
        }

        val builder = Builder()
            .setSession("ShieldGuard")
            .setMtu(1500)
            .addAddress("10.0.0.2", 32)
            .allowFamily(OsConstants.AF_INET)

        // Add numeric DNS servers only
        if (isIpAddress(upstream1)) {
            try { builder.addDnsServer(upstream1) } catch (e: Exception) { Log.w(TAG, "addDnsServer1 failed: ${e.message}") }
        } else {
            Log.i(TAG, "upstream1 is not an IP: $upstream1")
        }
        if (isIpAddress(upstream2) && upstream2 != upstream1) {
            try { builder.addDnsServer(upstream2) } catch (e: Exception) { Log.w(TAG, "addDnsServer2 failed: ${e.message}") }
        }

        // per-app rules from prefs or intent
        try {
            val prefs = getSharedPreferences("shieldguard_prefs", Context.MODE_PRIVATE)
            val allowedFromIntent = startIntent?.getStringArrayListExtra(EXTRA_ALLOWED_APPS)
            val blockedFromIntent = startIntent?.getStringArrayListExtra(EXTRA_BLOCKED_APPS)

            val allowedSet: Set<String> = when {
                allowedFromIntent != null && allowedFromIntent.isNotEmpty() -> allowedFromIntent.toSet()
                else -> prefs.getStringSet("allowed_apps", emptySet()) ?: emptySet()
            }
            val blockedSet: Set<String> = when {
                blockedFromIntent != null && blockedFromIntent.isNotEmpty() -> blockedFromIntent.toSet()
                else -> prefs.getStringSet("blocked_apps", emptySet()) ?: emptySet()
            }

            if (allowedSet.isNotEmpty()) {
                for (pkg in allowedSet) try { builder.addAllowedApplication(pkg) } catch (ex: Exception) { Log.w(TAG, "addAllowedApplication $pkg: ${ex.message}") }
            } else if (blockedSet.isNotEmpty()) {
                for (pkg in blockedSet) try { builder.addDisallowedApplication(pkg) } catch (ex: Exception) { Log.w(TAG, "addDisallowedApplication $pkg: ${ex.message}") }
            } else {
                Log.i(TAG, "no per-app rules applied")
            }
        } catch (e: Exception) { Log.w(TAG, "apply per-app rules failed: ${e.message}") }

        descriptor?.close()
        descriptor = try { builder.establish() } catch (e: Exception) { Log.e(TAG, "establish failed: ${e.message}"); null }

        descriptor?.also {
            running.set(true)
            provider = ProviderPicker.get(it, this)
            provider?.start()
            thread = Thread(this, "DnsVpnThread").apply { start() }
            registerNetworkCallback()
            Log.i(TAG, "VPN started (provider=${provider?.javaClass?.simpleName})")
        } ?: run {
            Log.e(TAG, "VPN descriptor null - not started")
        }
    }

    fun getLocalBlocklist(): Set<String> {
        return try {
            val prefs = getSharedPreferences("shieldguard_prefs", Context.MODE_PRIVATE)
            val raw = prefs.getStringSet("blocklist_domains", emptySet()) ?: emptySet()
            Log.i(TAG, "getLocalBlocklist loaded ${raw.size} items")
            raw.map { it.trim().lowercase().trimEnd('.') }.filter { it.isNotEmpty() }.toSet()
        } catch (e: Exception) {
            emptySet()
        }
    }

    private fun stopVpn() {
        if (!running.get()) return
        running.set(false)
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            networkCallback?.let { cm.unregisterNetworkCallback(it) }
            networkCallback = null
        } catch (e: Exception) { Log.w(TAG, "unregisterNetworkCallback failed: ${e.message}") }

        try { provider?.shutdown() } catch (e: Exception) { Log.w(TAG, "provider.shutdown failed: ${e.message}") }
        try { descriptor?.close() } catch (_: Exception) {}
        try { thread?.interrupt() } catch (_: Exception) {}

        descriptor = null
        provider = null
        thread = null

        Log.i(TAG, "VPN stopped")
        stopForeground(true)
        stopSelf()
    }

    override fun onDestroy() {
        super.onDestroy()
        stopVpn()
    }

    override fun run() {
        provider?.process()
    }

    fun resolveLocal(ip: IpPacket, msg: DnsMessage): Boolean {
        // Optional: local resolution hook
        return false
    }

    override fun protect(socket: DatagramSocket): Boolean = super.protect(socket)

    private fun registerNetworkCallback() {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val nc = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: android.net.Network) {
                    super.onAvailable(network)
                    mainHandler.post { if (!running.get()) startVpn(null) }
                }
                override fun onLost(network: android.net.Network) { super.onLost(network) }
            }
            cm.registerDefaultNetworkCallback(nc)
            networkCallback = nc
        } catch (ex: Exception) { Log.w(TAG, "registerNetworkCallback failed: ${ex.message}") }
    }
}
