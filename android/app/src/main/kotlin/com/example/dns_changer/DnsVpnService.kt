package com.example.dns_changer

import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import android.util.Log
import com.example.dns_changer.provider.ProviderPicker
import com.example.dns_changer.provider.Provider
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
    var upstream1: String = "1.1.1.1"
    var upstream2: String = "1.0.0.1"
    var port1 = 53
    var port2 = 53
    var queryMethod = ProviderPicker.UDP

    private var descriptor: ParcelFileDescriptor? = null
    private var thread: Thread? = null
    private var provider: Provider? = null
    internal var interruptFd: ParcelFileDescriptor? = null
    private val running = AtomicBoolean(false)

  // inside DnsVpnService.kt

override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
        ACTION_START -> {
            // DNS hosts
            intent.getStringExtra("dns1")?.let { upstream1 = it }
            intent.getStringExtra("dns2")?.let { upstream2 = it }

            // optional: query method (int) and ports (int)
            try {
                val qm = intent.getIntExtra("queryMethod", queryMethod)
                queryMethod = qm
            } catch (_: Exception) { /* ignore */ }

            try {
                val p1 = intent.getIntExtra("port1", port1)
                val p2 = intent.getIntExtra("port2", port2)
                port1 = p1
                port2 = p2
            } catch (_: Exception) { /* ignore */ }

            startVpn()
        }
        ACTION_STOP  -> stopVpn()
    }
    return START_STICKY
}


    private fun startVpn() {
        if (running.get()) return
        val builder = Builder()
            .setSession("ShieldGuard")
            .addAddress("10.0.0.2", 32)
            .addDnsServer(upstream1)
            .addDnsServer(upstream2)
           // .addRoute("0.0.0.0", 0)
            .allowFamily(OsConstants.AF_INET)
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
        // TODO: your RuleResolver logic here
        return false
    }

    /** Protect sockets from VPN */
    override fun protect(socket: DatagramSocket): Boolean = super.protect(socket)
}
