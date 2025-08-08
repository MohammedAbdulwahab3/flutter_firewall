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
    private val mainHandler = Handler(Looper.getMainLooper())

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
                startVpn()
            }
            ACTION_STOP -> stopVpn()
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
               // .setSmallIcon(android.R.drawable.stat_sys_vpn) // replace with your icon
                .setOngoing(true)
                .build()
            startForeground(1, notification)
        } catch (ex: Exception) {
            Log.w("DnsVpnService", "startForeground failed: ${ex.message}")
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        try {
            val restartIntent = Intent(applicationContext, DnsVpnService::class.java).apply {
                action = ACTION_START
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_CANCEL_CURRENT else PendingIntent.FLAG_CANCEL_CURRENT
            val pending = PendingIntent.getService(applicationContext, 0, restartIntent, flags)
            val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val triggerAt = System.currentTimeMillis() + 1000L
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
            Log.i("DnsVpnService", "Scheduled restart after task removed")
        } catch (ex: Exception) {
            Log.w("DnsVpnService", "onTaskRemoved schedule restart failed: ${ex.message}")
        }
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

        // Add DNS servers only when numeric (VpnService.Builder.addDnsServer requires numeric IPs)
        if (isIpAddress(upstream1)) {
            try { builder.addDnsServer(upstream1) } catch (_: Exception) {}
        } else {
            Log.i("DnsVpnService", "Using domain upstream: $upstream1")
        }
        if (isIpAddress(upstream2) && upstream2 != upstream1) {
            try { builder.addDnsServer(upstream2) } catch (_: Exception) {}
        }

        // IMPORTANT: add default route only if you want device-wide traffic captured
        // builder.addRoute("0.0.0.0", 0)

        Log.i("DnsVpnService", "Starting VPN: method=${queryMethod} upstream1=${upstream1}:${port1} upstream2=${upstream2}:${port2}")

        descriptor?.close()
        descriptor = builder.establish()
        descriptor?.also {
            running.set(true)
            provider = ProviderPicker.get(it, this)
            provider!!.start()
            thread = Thread(this, "DnsVpnThread").apply { start() }
            registerNetworkCallback()
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

    private fun registerNetworkCallback() {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val nc = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: android.net.Network) {
                    super.onAvailable(network)
                    Log.i("DnsVpnService", "Network available")
                    // If provider not running, attempt to restart on main thread (ensure safe access)
                    mainHandler.post {
                        if (!running.get()) {
                            Log.i("DnsVpnService", "Network came back; attempting to restart VPN")
                            startVpn()
                        }
                    }
                }
                override fun onLost(network: android.net.Network) {
                    super.onLost(network)
                    Log.i("DnsVpnService", "Network lost")
                }
            }
            cm.registerDefaultNetworkCallback(nc)
        } catch (ex: Exception) {
            Log.w("DnsVpnService", "registerNetworkCallback failed: ${ex.message}")
        }
    }
}
