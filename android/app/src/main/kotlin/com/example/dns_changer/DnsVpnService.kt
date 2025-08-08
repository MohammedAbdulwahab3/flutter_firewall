// package com.example.dns_changer
// // Add this import at top of DnsVpnService.kt (if not already present)



// import android.app.PendingIntent
// import android.content.Intent
// import android.net.VpnService
// import android.os.ParcelFileDescriptor
// import android.system.OsConstants
// import android.util.Log
// import android.util.Patterns
// import com.example.dns_changer.provider.ProviderPicker
// import com.example.dns_changer.provider.Provider
// import org.minidns.dnsmessage.DnsMessage
// import org.pcap4j.packet.IpPacket
// import java.net.DatagramSocket
// import java.util.concurrent.atomic.AtomicBoolean

// class DnsVpnService : VpnService(), Runnable {
//     companion object {
//         const val ACTION_START = "com.example.dns_changer.START"
//         const val ACTION_STOP  = "com.example.dns_changer.STOP"
//     }

//     // configured by Flutter via MethodChannel
//     var upstream1: String = "1.1.1.1"
//     var upstream2: String = "1.0.0.1"
//     var port1 = 53
//     var port2 = 53
//     var queryMethod = ProviderPicker.UDP

//     private var descriptor: ParcelFileDescriptor? = null
//     private var thread: Thread? = null
//     private var provider: Provider? = null
//     internal var interruptFd: ParcelFileDescriptor? = null
//     private val running = AtomicBoolean(false)

//   // inside DnsVpnService.kt

// override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
//     when (intent?.action) {
//         ACTION_START -> {
//             // DNS hosts
//             intent.getStringExtra("dns1")?.let { upstream1 = it }
//             intent.getStringExtra("dns2")?.let { upstream2 = it }

//             // optional: query method (int) and ports (int)
//             try {
//                 val qm = intent.getIntExtra("queryMethod", queryMethod)
//                 queryMethod = qm
//             } catch (_: Exception) { /* ignore */ }

//             try {
//                 val p1 = intent.getIntExtra("port1", port1)
//                 val p2 = intent.getIntExtra("port2", port2)
//                 port1 = p1
//                 port2 = p2
//             } catch (_: Exception) { /* ignore */ }

//             startVpn()
//         }
//         ACTION_STOP  -> stopVpn()
//     }
//     return START_STICKY
// }

// // DnsVpnService.kt: helper (inside class)

// private fun isIpAddress(addr: String?): Boolean {
//     if (addr == null) return false
//     return Patterns.IP_ADDRESS.matcher(addr).matches()
// }

// private fun startVpn() {
//     if (running.get()) return

//     val builder = Builder()
//         .setSession("ShieldGuard")
//         .setMtu(1500)
//         .addAddress("10.0.0.2", 32)
//         .allowFamily(OsConstants.AF_INET)

//     // Add numeric DNS servers only (VpnService requires numeric addresses)
//     if (isIpAddress(upstream1)) {
//         try { builder.addDnsServer(upstream1) } catch (_: Exception) {}
//     } else {
//         Log.i("DnsVpnService", "Skipping addDnsServer for non-IP upstream1: $upstream1")
//     }

//     if (isIpAddress(upstream2) && upstream2 != upstream1) {
//         try { builder.addDnsServer(upstream2) } catch (_: Exception) {}
//     } else if (!isIpAddress(upstream2)) {
//         Log.i("DnsVpnService", "Skipping addDnsServer for non-IP upstream2: $upstream2")
//     }

//     // IMPORTANT: add default route so app sees all traffic (TUN receives everything).
//     // We will forward the UDP traffic from the TUN using user-space sockets.
//     try {
//        // builder.addRoute("0.0.0.0", 0)
//     } catch (_: Exception) {
//         Log.w("DnsVpnService", "addRoute failed")
//     }

//     Log.i("DnsVpnService", "Starting VPN: method=${queryMethod} upstream1=${upstream1}:${port1} upstream2=${upstream2}:${port2}")

//     descriptor?.close()
//     descriptor = builder.establish()
//     descriptor?.also {
//         running.set(true)
//         provider = ProviderPicker.get(it, this)
//         provider!!.start()
//         thread = Thread(this, "DnsVpnThread").apply { start() }
//         Log.i("DnsVpnService", "VPN started")
//     }
// }


//     private fun stopVpn() {
//         if (!running.get()) return
//         running.set(false)
//         provider?.shutdown()
//         descriptor?.close()
//         interruptFd?.close()
//         thread?.interrupt()
//         Log.i("DnsVpnService", "VPN stopped")
//     }

//     override fun onDestroy() {
//         super.onDestroy()
//         stopVpn()
//     }

//     override fun run() {
//         provider?.process()
//     }

//     /** Allow provider to resolve via local rules (e.g. blocklist) */
//     fun resolveLocal(ip: IpPacket, msg: DnsMessage): Boolean {
//         // TODO: your RuleResolver logic here
//         return false
//     }

//     /** Protect sockets from VPN */
//     override fun protect(socket: DatagramSocket): Boolean = super.protect(socket)
// }



package com.example.dns_changer

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
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

class DnsVpnService : VpnService(), Runnable {
    companion object {
        const val ACTION_START = "com.example.dns_changer.START"
        const val ACTION_STOP  = "com.example.dns_changer.STOP"
    }

    // configured by Flutter via MethodChannel
    var upstream1: String = "dns.nextdns.io/46bded"
    var upstream2: String = ""
    var port1 = 443
    var port2 = 443
    var queryMethod = ProviderPicker.HTTPS

    private var descriptor: ParcelFileDescriptor? = null
    private var thread: Thread? = null
    private var provider: Provider? = null
    internal var interruptFd: ParcelFileDescriptor? = null
    private val running = AtomicBoolean(false)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
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
                startVpn()
            }
            ACTION_STOP -> stopVpn()
        }
        return START_STICKY
    }

    private fun isIpAddress(addr: String?): Boolean {
        if (addr == null) return false
        return Patterns.IP_ADDRESS.matcher(addr).matches()
    }

    private fun startVpn() {
        if (running.get()) return

        val builder = Builder()
            .setSession("ShieldGuard")
            .setMtu(1500)
            .addAddress("10.0.0.2", 32)
            .allowFamily(OsConstants.AF_INET)

        // Optional: restrict to single app during testing to avoid device-wide breakage.
        // Uncomment and replace package name with the test app (e.g., "com.android.chrome") when debugging.
        /*
        try {
            builder.addAllowedApplication("com.android.chrome")
        } catch (e: PackageManager.NameNotFoundException) {
            Log.w("DnsVpnService", "allowed package not found: ${e.message}")
        } catch (e: SecurityException) {
            Log.w("DnsVpnService", "cannot add allowed application: ${e.message}")
        }
        */

        // Add DNS servers only when numeric (VpnService.Builder.addDnsServer requires numeric IPs)
        // But for DoH/DoT we're passing a hostname to provider via upstream1; still add numeric fallback if present.
        if (isIpAddress(upstream1)) {
            try { builder.addDnsServer(upstream1) } catch (_: Exception) {}
        } else {
            Log.i("DnsVpnService", "Using domain upstream: $upstream1")
        }
        if (isIpAddress(upstream2) && upstream2 != upstream1) {
            try { builder.addDnsServer(upstream2) } catch (_: Exception) {}
        }

        // IMPORTANT: add default route so the TUN sees traffic for allowed apps.
        // If you only allow a single app (via addAllowedApplication), keeping the route ensures that app's traffic is routed to the TUN.
        try {
           // builder.addRoute("0.0.0.0", 0)
        } catch (_: Exception) {
            Log.w("DnsVpnService", "addRoute failed")
        }

        Log.i("DnsVpnService", "Starting VPN: method=${queryMethod} upstream1=${upstream1}:${port1} upstream2=${upstream2}:${port2}")

        descriptor?.close()
        descriptor = builder.establish()
        descriptor?.also {
            running.set(true)
            provider = ProviderPicker.get(it, this)
            provider!!.start()
            thread = Thread(this, "DnsVpnThread").apply { start() }
            Log.i("DnsVpnService", "VPN started")
        }
    }

    private fun stopVpn() {
        if (!running.get()) return
        running.set(false)
        provider?.shutdown()
        descriptor?.close()
        interruptFd?.close()
        thread?.interrupt()
        Log.i("DnsVpnService", "VPN stopped")
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
        // TODO: implement rule resolver if you need local answers
        return false
    }

    /** Protect sockets from VPN */
    override fun protect(socket: DatagramSocket): Boolean = super.protect(socket)
}
