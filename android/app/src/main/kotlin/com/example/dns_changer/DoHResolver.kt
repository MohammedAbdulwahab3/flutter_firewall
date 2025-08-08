package com.example.dns_changer

import android.util.Log
import okhttp3.*
import org.xbill.DNS.*
import java.io.IOException

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.Response
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody


class DoHResolver(private val dohUrl: String) {

    private val client = OkHttpClient()

    fun resolve(domain: String, callback: (List<String>?) -> Unit) {
        val name = Name.fromString("$domain.")
        val query = Message.newQuery(Record.newRecord(name, Type.A, DClass.IN))
        val data = query.toWire()

        val request = Request.Builder()
            .url(dohUrl)
            .addHeader("Content-Type", "application/dns-message")
            .addHeader("Accept", "application/dns-message")
            .post(RequestBody.create("application/dns-message".toMediaTypeOrNull(), data))
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                Log.e("DoHResolver", "Request failed: ${e.message}")
                callback(null)
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    if (!it.isSuccessful) {
                        Log.e("DoHResolver", "Unexpected response: $response")
                        callback(null)
                        return
                    }

                    val responseBytes = it.body?.bytes()
                    if (responseBytes != null) {
                        val msg = Message(responseBytes)
                        val ips = msg.getSectionArray(Section.ANSWER)
                            .filterIsInstance<ARecord>()
                            .map { record -> record.address.hostAddress }
                        callback(ips)
                    } else {
                        callback(null)
                    }
                }
            }
        })
    }
}
