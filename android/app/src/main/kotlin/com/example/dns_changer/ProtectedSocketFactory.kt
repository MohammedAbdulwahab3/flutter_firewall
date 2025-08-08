package com.example.dns_changer.provider

import com.example.dns_changer.DnsVpnService
import java.net.InetAddress
import java.net.Socket
import javax.net.SocketFactory

/**
 * Wraps a SocketFactory and calls VpnService.protect(socket) on every socket created.
 * Use with OkHttpClient.Builder().socketFactory(...) to ensure DoH sockets bypass the VPN.
 */
class ProtectedSocketFactory(
    private val base: SocketFactory,
    private val service: DnsVpnService
) : SocketFactory() {

    override fun createSocket(): Socket {
        val s = base.createSocket()
        try { service.protect(s) } catch (_: Exception) {}
        return s
    }

    override fun createSocket(host: String, port: Int): Socket {
        val s = base.createSocket(host, port)
        try { service.protect(s) } catch (_: Exception) {}
        return s
    }

    override fun createSocket(address: InetAddress, port: Int): Socket {
        val s = base.createSocket(address, port)
        try { service.protect(s) } catch (_: Exception) {}
        return s
    }

    override fun createSocket(host: String, port: Int, localAddr: InetAddress, localPort: Int): Socket {
        val s = base.createSocket(host, port, localAddr, localPort)
        try { service.protect(s) } catch (_: Exception) {}
        return s
    }

    override fun createSocket(address: InetAddress, port: Int, localAddr: InetAddress, localPort: Int): Socket {
        val s = base.createSocket(address, port, localAddr, localPort)
        try { service.protect(s) } catch (_: Exception) {}
        return s
    }
}
