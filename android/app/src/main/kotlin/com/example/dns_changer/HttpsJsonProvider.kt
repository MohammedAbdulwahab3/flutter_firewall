package com.example.dns_changer.provider

import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import android.util.Log
import com.example.dns_changer.DnsVpnService
import com.google.gson.JsonElement
import com.google.gson.JsonParser
import okhttp3.*
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.minidns.dnsmessage.DnsMessage
import org.minidns.dnsname.DnsName
import org.minidns.record.*
import org.pcap4j.packet.IpPacket
import org.pcap4j.packet.IpSelector
import org.pcap4j.packet.UdpPacket
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.FileDescriptor
import java.net.InetAddress
import java.util.*
import java.util.concurrent.TimeUnit
import javax.net.SocketFactory

class HttpsJsonProvider(
    descriptor: ParcelFileDescriptor,
    svc: DnsVpnService
) : Provider(descriptor, svc) {



    companion object { private const val TAG = "HttpsJsonProvider"; private const val HTTPS_PREFIX = "https://" }

    private val whqList = WhqList()

    private val httpClient: OkHttpClient by lazy {
        val protectedSocketFactory = ProtectedSocketFactory(SocketFactory.getDefault(), service)
        OkHttpClient.Builder()
            .socketFactory(protectedSocketFactory)
            .connectTimeout(8, TimeUnit.SECONDS)
            .readTimeout(8, TimeUnit.SECONDS)
            .writeTimeout(8, TimeUnit.SECONDS)
            .addInterceptor { chain ->
                val req = chain.request().newBuilder()
                    .header("Accept", "application/dns-json")
                    .build()
                chain.proceed(req)
            }
            .build()
    }

    private var mInterruptFd: FileDescriptor? = null
    private var mBlockFd: FileDescriptor? = null

    override fun process() {
        try {
            val pipes = Os.pipe()
            mInterruptFd = pipes[0]; mBlockFd = pipes[1]
        } catch (e: Exception) {
            Log.w(TAG, "pipe failed: ${e.message}")
        }

        val tunFd = descriptor.fileDescriptor
        val input = FileInputStream(tunFd)
        val output = FileOutputStream(tunFd)
        val packetBuf = ByteArray(32767)

        try {
            while (running) {
                val needsPollOut = hasQueuedWrites()
                val deviceFd = StructPollfd().apply {
                    fd = input.fd
                    events = OsConstants.POLLIN.toShort()
                    if (needsPollOut) events = (events.toInt() or OsConstants.POLLOUT).toShort()
                    revents = 0
                }
                val blockFd = StructPollfd().apply {
                    fd = mBlockFd
                    events = (OsConstants.POLLHUP or OsConstants.POLLERR).toShort()
                    revents = 0
                }

                val polls = arrayListOf<StructPollfd>()
                polls.add(deviceFd); polls.add(blockFd)

                try { Os.poll(polls.toTypedArray(), 1000) } catch (e: Exception) { Log.w(TAG, "poll fail: ${e.message}") }

                if (blockFd.revents.toInt() != 0) {
                    Log.i(TAG, "Told to stop (blockFd)"); running = false; return
                }

                val iter = whqList.iterator()
                while (iter.hasNext()) {
                    val w = iter.next()
                    if (w.completed) {
                        try { handleDnsResponse(w.packet, w.result) } catch (e: Exception) { Log.w(TAG, "handleDnsResponse error: ${e.message}") }
                        finally { //iter.remove() 
                            }
                    }
                }

                try { if ((deviceFd.revents.toInt() and OsConstants.POLLOUT) != 0) writeToDevice(output) } catch (e: Exception) { Log.w(TAG, "writeToDevice error: ${e.message}") }
                try { if ((deviceFd.revents.toInt() and OsConstants.POLLIN) != 0) readDevice(input, packetBuf) } catch (e: Exception) { Log.w(TAG, "readDevice error: ${e.message}") }
            }
        } finally {
            try { input.close() } catch (_: Exception) {}
            try { output.close() } catch (_: Exception) {}
            whqList.clear()
            try { if (mInterruptFd != null) Os.close(mInterruptFd) } catch (_: Exception) {}
            try { if (mBlockFd != null) Os.close(mBlockFd) } catch (_: Exception) {}
        }
    }

    override fun handleDnsRequest(packetData: ByteArray) {
        val ip = try { IpSelector.newPacket(packetData, 0, packetData.size) as IpPacket } catch (e: Exception) { return }
        val udp = ip.payload as? UdpPacket ?: return
        val dstPort = try { udp.header.dstPort.valueAsInt() } catch (e: Exception) { return }
        if (dstPort != 53) return

        val raw = udp.payload?.rawData ?: return
        val dnsMsg = try { DnsMessage(raw) } catch (e: Exception) { return }
        val question = try { dnsMsg.question } catch (e: Exception) { return }
        if (question == null) return

        try { Log.d(TAG, "DoH JSON query ${question.name}") } catch (_: Exception) {}

        if (service.resolveLocal(ip, dnsMsg)) return
        if (shouldBlock(dnsMsg)) {
            try {
                val nx = raw.copyOf()
                val flags = 0x8003
                nx[2] = ((flags shr 8) and 0xFF).toByte()
                nx[3] = (flags and 0xFF).toByte()
                handleDnsResponse(ip, nx)
            } catch (e: Exception) { Log.w(TAG, "craft NX failed: ${e.message}") }
            return
        }

        val uriHost = service.upstream1
        val url = if (uriHost.contains("/")) HTTPS_PREFIX + uriHost else HTTPS_PREFIX + uriHost + "/dns-query"

        whqList.add(object : WaitingHttpsRequest(ip) {
            override fun doRequest() {
                try {
                    val httpUrl = url.toHttpUrlOrNull()?.newBuilder()
                        ?.addQueryParameter("name", dnsMsg.question.name.toString())
                        ?.addQueryParameter("type", dnsMsg.question.type.name)
                        ?.build() ?: run {
                            result = raw; completed = true; return
                        }

                    val request = Request.Builder()
                        .url(httpUrl)
                        .get()
                        .header("Accept", "application/dns-json")
                        .build()

                    httpClient.newCall(request).enqueue(object : Callback {
                        override fun onFailure(call: Call, e: java.io.IOException) { result = raw; completed = true }
                        override fun onResponse(call: Call, response: Response) {
                            response.use {
                                if (!it.isSuccessful) { result = raw; completed = true; return }
                                try {
                                    val bodyText = it.body?.string() ?: ""
                                    val jsonObj = JsonParser.parseString(bodyText).asJsonObject

                                    val builder = dnsMsg.asBuilder()
                                    if (jsonObj.has("Answer")) {
                                        val answers = jsonObj.getAsJsonArray("Answer")
                                        for (ae: JsonElement in answers) {
                                            try {
                                                val ans = ae.asJsonObject
                                                val typeInt = ans.get("type").asInt
                                                val type = Record.TYPE.getType(typeInt)
                                                val dataStr = ans.get("data").asString
                                                var recordData: Data? = null
                                                when (type) {
                                                    Record.TYPE.A -> recordData = A(dataStr)
                                                    Record.TYPE.AAAA -> recordData = AAAA(dataStr)
                                                    Record.TYPE.CNAME -> recordData = CNAME(dataStr)
                                                    Record.TYPE.MX -> {
                                                        val pref = if (ans.has("pref")) ans.get("pref").asInt else 5
                                                        recordData = MX(pref, dataStr)
                                                    }
                                                    Record.TYPE.SOA -> {
                                                        val sections = dataStr.split(" ")
                                                        if (sections.size >= 7) {
                                                            recordData = SOA(
                                                                sections[0],
                                                                sections[1],
                                                                java.lang.Long.valueOf(sections[2]),
                                                                Integer.valueOf(sections[3]),
                                                                Integer.valueOf(sections[4]),
                                                                Integer.valueOf(sections[5]),
                                                                java.lang.Long.valueOf(sections[6])
                                                            )
                                                        }
                                                    }
                                                    Record.TYPE.DNAME -> recordData = DNAME(dataStr)
                                                    Record.TYPE.NS -> recordData = NS(DnsName.from(dataStr))
                                                    Record.TYPE.TXT -> recordData = TXT(dataStr.toByteArray())
                                                    else -> {}
                                                }
                                                if (recordData != null) {
                                                    val name = if (ans.has("name")) ans.get("name").asString else dnsMsg.question.name.toString()
                                                    val ttl = if (ans.has("TTL")) ans.get("TTL").asLong else 60L
                                                    builder.addAnswer(Record(name, type, 1, ttl, recordData))
                                                }
                                            } catch (ex: Exception) {
                                                Log.w(TAG, "parse answer item failed: ${ex.message}")
                                            }
                                        }
                                    }
                                    result = builder.setQrFlag(true).build().toArray()
                                    completed = true
                                } catch (ex: Exception) {
                                    result = raw
                                    completed = true
                                }
                            }
                        }
                    })
                } catch (ex: Exception) {
                    result = raw
                    completed = true
                }
            }
        })
    }

    abstract class WaitingHttpsRequest(val packet: IpPacket) {
        @Volatile var completed = false
        @Volatile var result: ByteArray = ByteArray(0)
        abstract fun doRequest()
    }

    class WhqList : Iterable<WaitingHttpsRequest> {
        private val list = LinkedList<WaitingHttpsRequest>()
        @Synchronized fun add(r: WaitingHttpsRequest) {
            list.add(r)
            try { r.doRequest() } catch (e: Exception) { Log.w(TAG, "doRequest failed: ${e.message}") }
        }
        @Synchronized override fun iterator(): Iterator<WaitingHttpsRequest> = list.iterator()
        @Synchronized fun clear() = list.clear()
    }
}
