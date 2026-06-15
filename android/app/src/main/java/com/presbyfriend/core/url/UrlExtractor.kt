package com.presbyfriend.core.url

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import org.jsoup.nodes.Document

object UrlExtractor {

    private val client = OkHttpClient.Builder()
        .followRedirects(true)
        .build()

    suspend fun extract(url: String): Result<String> = withContext(Dispatchers.IO) {
        try {
            val request = Request.Builder()
                .url(url)
                .header("User-Agent", "Mozilla/5.0 (compatible; PresbyFriend/1.0)")
                .build()

            val response = client.newCall(request).execute()
            val html = response.body?.string() ?: return@withContext Result.failure(
                Exception("Empty response")
            )

            val doc: Document = Jsoup.parse(html)
            val body = doc.body()

            // Remove script, style, nav, footer elements
            body.select("script, style, nav, footer, header, .sidebar, .ad, .advertisement")
                .remove()

            val text = body.text()
                .replace(Regex("\\s+"), " ")
                .trim()

            if (text.isBlank()) {
                Result.failure(Exception("No readable text found"))
            } else {
                Result.success(text)
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
