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
import android.app.AlarmManager
import android.app.PendingIntent

class DnsVpnService : VpnService(), Runnable {
    companion object {
        const val ACTION_START = "com.example.dns_changer.START"
        const val ACTION_STOP  = "com.example.dns_changer.STOP"
        const val EXTRA_ALLOWED_APPS = "allowedApps"
        const val EXTRA_BLOCKED_APPS = "blockedApps"
    }

    // configured by Flutter via MethodChannel / MainActivity
    var upstream1: String = "dns.nextdns.io/775691"
    var upstream2: String = "https://dns.nextdns.io/775691"
    var port1 = 443
    var port2 = 443
    var queryMethod = ProviderPicker.HTTPS

    // runtime state
    private var descriptor: ParcelFileDescriptor? = null
    private var thread: Thread? = null
    private var provider: Provider? = null
    private val running = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())

    // Keep a reference to the network callback so we can unregister it
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

     // NEW: whether to enforce the local/blocklist stored in SharedPreferences.
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
                    Log.i("DnsVpnService", "useLocalBlocklist=$useLocalBlocklist")
                } catch (_: Exception) {}


                Log.i("DnsVpnService", "Received START intent: upstream1=$upstream1 upstream2=$upstream2 queryMethod=$queryMethod")
                startVpn(intent)

                
            }
            ACTION_STOP -> stopVpn()
            else -> {
                Log.i("DnsVpnService", "onStartCommand other action: ${intent?.action}")
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
            Log.w("DnsVpnService", "startForeground failed: ${ex.message}")
        }
    }

    private fun isIpAddress(addr: String?): Boolean {
        if (addr == null) return false
        return Patterns.IP_ADDRESS.matcher(addr).matches()
    }

    private fun startVpn(startIntent: Intent?) {
        if (running.get()) return

        val builder = Builder()
            .setSession("ShieldGuard")
            .setMtu(1500)
            .addAddress("10.0.0.2", 32)
            .allowFamily(OsConstants.AF_INET)

        // Add DNS servers only when numeric (VpnService.Builder.addDnsServer requires numeric IPs)
        if (isIpAddress(upstream1)) {
            try { builder.addDnsServer(upstream1) } catch (_: Exception) {}
        } else {
            Log.i("DnsVpnService", "Using domain upstream: $upstream1")
        }
        if (isIpAddress(upstream2) && upstream2 != upstream1) {
            try { builder.addDnsServer(upstream2) } catch (_: Exception) {}
        }
        Log.i("DnsVpnService", "Starting VPN: method=${queryMethod} upstream1=${upstream1}:${port1} upstream2=${upstream2}:${port2}")

        // ----- APPLY PER-APP RULES (allowed takes precedence) -----
        try {
            val prefs = getSharedPreferences("shieldguard_prefs", Context.MODE_PRIVATE)
            // Intent extras may include allowed/blocked lists to apply immediately
            val allowedFromIntent = startIntent?.getStringArrayListExtra(EXTRA_ALLOWED_APPS)
            val blockedFromIntent = startIntent?.getStringArrayListExtra(EXTRA_BLOCKED_APPS)

            // prefer extras if present, otherwise read persisted sets
            val allowedSet: Set<String> = when {
                allowedFromIntent != null && allowedFromIntent.isNotEmpty() -> allowedFromIntent.toSet()
                else -> prefs.getStringSet("allowed_apps", emptySet()) ?: emptySet()
            }
            val blockedSet: Set<String> = when {
                blockedFromIntent != null && blockedFromIntent.isNotEmpty() -> blockedFromIntent.toSet()
                else -> prefs.getStringSet("blocked_apps", emptySet()) ?: emptySet()
            }

            if (allowedSet.isNotEmpty()) {
                // Allow-mode: only these packages go through VPN
                for (pkg in allowedSet) {
                    try {
                        builder.addAllowedApplication(pkg)
                        Log.i("DnsVpnService", "addAllowedApplication: $pkg")
                    } catch (ex: PackageManager.NameNotFoundException) {
                        Log.w("DnsVpnService", "Package not found for addAllowedApplication: $pkg")
                    } catch (ex: SecurityException) {
                        Log.w("DnsVpnService", "addAllowedApplication SecurityException for $pkg: ${ex.message}")
                    } catch (ex: Exception) {
                        Log.w("DnsVpnService", "addAllowedApplication failed for $pkg: ${ex.message}")
                    }
                }
            } else if (blockedSet.isNotEmpty()) {
                // Block-mode: exclude these packages from VPN
                for (pkg in blockedSet) {
                    try {
                        builder.addDisallowedApplication(pkg)
                        Log.i("DnsVpnService", "addDisallowedApplication: $pkg")
                    } catch (ex: PackageManager.NameNotFoundException) {
                        Log.w("DnsVpnService", "Package not found for addDisallowedApplication: $pkg")
                    } catch (ex: SecurityException) {
                        Log.w("DnsVpnService", "addDisallowedApplication SecurityException for $pkg: ${ex.message}")
                    } catch (ex: Exception) {
                        Log.w("DnsVpnService", "addDisallowedApplication failed for $pkg: ${ex.message}")
                    }
                }
            } else {
                Log.i("DnsVpnService", "No per-app rules applied (allowed empty && blocked empty)")
            }
        } catch (e: Exception) {
            Log.w("DnsVpnService", "Failed to apply per-app rules: ${e.message}")
        }
        // ----- END per-app rules -----

        // NOTE: do NOT add a 0.0.0.0 route here unless you want device-wide capture
        // builder.addRoute("0.0.0.0", 0)

        Log.i("DnsVpnService", "Starting VPN: method=${queryMethod} upstream1=${upstream1}:${port1} upstream2=${upstream2}:${port2}")

        descriptor?.close()
        descriptor = try {
            builder.establish()
        } catch (e: Exception) {
            Log.e("DnsVpnService", "Failed to establish VPN: ${e.message}")
            null
        }

        descriptor?.also {
            running.set(true)
            provider = ProviderPicker.get(it, this)
            provider?.start()
            thread = Thread(this, "DnsVpnThread").apply { start() }
            registerNetworkCallback()
            Log.i("DnsVpnService", "VPN started")
        } ?: run {
            Log.e("DnsVpnService", "descriptor is null - VPN not established")
        }
    }

       /**
     * Helper for providers to read the local blocklist that the Flutter UI pushes into SharedPreferences.
     * Returns a normalized (lowercase, no trailing dot) set.
     */
    fun getLocalBlocklist(): Set<String> {
        return try {
            val prefs = getSharedPreferences("shieldguard_prefs", Context.MODE_PRIVATE)
            val raw = prefs.getStringSet("blocklist_domains", emptySet()) ?: emptySet()
            raw.map { it.trim().lowercase().trimEnd('.') }.filter { it.isNotEmpty() }.toSet()
        } catch (e: Exception) {
            emptySet()
        }
    }

    private fun stopVpn() {
        if (!running.get()) return
        running.set(false)

        // unregister network callback if any
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            networkCallback?.let { cm.unregisterNetworkCallback(it) }
            networkCallback = null
        } catch (e: Exception) {
            Log.w("DnsVpnService", "unregisterNetworkCallback failed: ${e.message}")
        }

        try {
            provider?.shutdown()
        } catch (e: Exception) {
            Log.w("DnsVpnService", "provider.shutdown failed: ${e.message}")
        }

        try { descriptor?.close() } catch (_: Exception) {}
        try { thread?.interrupt() } catch (_: Exception) {}

        descriptor = null
        provider = null
        thread = null

        Log.i("DnsVpnService", "VPN stopped")
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

    /** Allow provider to resolve via local rules (e.g. blocklist) */
    fun resolveLocal(ip: IpPacket, msg: DnsMessage): Boolean {
        // TODO: implement rule resolver if you want DNS to be answered locally for some domains
        return false
    }

    /** Protect sockets from VPN (datagram) */
    override fun protect(socket: DatagramSocket): Boolean = super.protect(socket)

    private fun registerNetworkCallback() {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val nc = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: android.net.Network) {
                    super.onAvailable(network)
                    Log.i("DnsVpnService", "Network available")
                    mainHandler.post {
                        if (!running.get()) {
                            Log.i("DnsVpnService", "Network came back; attempting to restart VPN")
                            startVpn(null)
                        }
                    }
                }
                override fun onLost(network: android.net.Network) {
                    super.onLost(network)
                    Log.i("DnsVpnService", "Network lost")
                }
            }
            cm.registerDefaultNetworkCallback(nc)
            networkCallback = nc
        } catch (ex: Exception) {
            Log.w("DnsVpnService", "registerNetworkCallback failed: ${ex.message}")
        }
    }
}
