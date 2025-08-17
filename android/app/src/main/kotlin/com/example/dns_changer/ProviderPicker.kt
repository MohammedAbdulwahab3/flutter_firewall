package com.example.dns_changer.provider

import android.os.ParcelFileDescriptor
import com.example.dns_changer.DnsVpnService
import com.example.dns_changer.provider.HttpsIetfProvider
import com.example.dns_changer.provider.TcpProvider

object ProviderPicker {
    const val UDP   = 0
    const val TCP   = 1
    const val HTTPS = 2        // DoH (IETF binary) - earlier provider
    const val TLS   = 3        // DoT
    const val HTTPS_JSON = 4   // DoH JSON format

    fun get(
        descriptor: ParcelFileDescriptor,
        service: DnsVpnService
    ): Provider = when (service.queryMethod) {
        UDP   -> UdpProvider(descriptor, service)
        TCP   -> TcpProvider(descriptor, service)
        HTTPS -> HttpsIetfProvider(descriptor, service)
        TLS   -> TlsProvider(descriptor, service)
        HTTPS_JSON -> HttpsJsonProvider(descriptor, service)
        else  -> UdpProvider(descriptor, service)
    }
}
