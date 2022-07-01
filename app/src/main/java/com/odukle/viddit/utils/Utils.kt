@file:Suppress("BlockingMethodInNonBlockingContext")

package com.odukle.viddit.utils

import android.app.Activity
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.widget.Toast
import com.google.gson.JsonParser
import com.odukle.viddit.MainActivity.Companion.toast
import com.odukle.viddit.models.SubReddit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import net.dean.jraw.models.SubredditSort
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.SocketTimeoutException
import java.util.*

const val USER_LESS = "<userless>"
private const val TAG = "Utils"
const val SUBREDDIT_FRAGMENT = "subredditFragment"
const val SUBREDDIT_NAME = "subredditName"
const val SORTING = "sorting"
const val IS_USER = "isUser"
const val LOAD_FRONT_PAGE = "loadfp"
const val JSON_LIST = "jList"
const val ADAPTER_POSITION = "adapterPos"

// sorting
const val HOT = "hot"
const val NEW = "new"
const val TOP = "top"
const val RISING = "rising"
const val CONTROVERSIAL = "controversial"


fun View.show() {
    mainScope().launch {
        this@show.visibility = View.VISIBLE
    }
}

fun View.hide() {
    mainScope().launch {
        this@hide.visibility = View.GONE
    }
}

fun ioScope() = CoroutineScope(Dispatchers.IO)
fun mainScope() = CoroutineScope(Dispatchers.Main)
fun defScope() = CoroutineScope(Dispatchers.Default)

fun longToast(context: Context, text: String) {
    context as Activity
    context.runOnUiThread {
        toast.cancel()
        toast = Toast.makeText(context, text, Toast.LENGTH_LONG).apply { show() }
    }
}

fun shortToast(context: Context, text: String) {
    context as Activity
    context.runOnUiThread {
        toast.cancel()
        toast = Toast.makeText(context, text, Toast.LENGTH_SHORT).apply { show() }
    }
}

fun Long.toTimeAgo(): String {
    return when (val hr = ((Calendar.getInstance().timeInMillis - this * 1000L) / 3600000L)) {
        0L -> ((Calendar.getInstance().timeInMillis - this * 1000L) / 60000L).toString() + "m"
        in 1 until 24 -> hr.toString() + "h"
        in 24 until 168 -> (hr / 24).toString() + "d"
        in 168 until Integer.MAX_VALUE -> (hr / (24 * 7)).toString() + "w"
        else -> "xxx"
    }
}

suspend fun getUserIcon(user: String, client: OkHttpClient) = withContext(Dispatchers.IO) {
    try {
        val request = Request.Builder()
            .url("https://www.reddit.com/user/$user/about/.json")
            .get()
            .build()

        val response = client.newCall(request).execute()
        val json = response.body?.string()
        val jsonObject = JsonParser.parseString(json).asJsonObject
        val data = jsonObject["data"].asJsonObject
        return@withContext data["icon_img"].asString.replace("amp;", "")
    } catch (e: Exception) {
        if (e !is SocketTimeoutException) {
            Log.e(TAG, "getSubreddits: ${e.stackTraceToString()}")
        }
        return@withContext ""
    }
}

suspend fun getSubredditInfo(subreddit: String, client: OkHttpClient, isUser: Boolean = false): SubReddit = withContext(Dispatchers.IO) {

    try {
        val request = Request.Builder()
            .url("https://www.reddit.com/$subreddit/about.json")
            .get()
            .build()

        val response = client.newCall(request).execute()
        val json = response.body?.string()
        val jsonObject = JsonParser.parseString(json).asJsonObject
        val data = if (!isUser) jsonObject["data"].asJsonObject else jsonObject["data"].asJsonObject["subreddit"].asJsonObject
        val title = try {
            data["title"].asString
        } catch (e: Exception) {
            "null"
        }
        val titlePrefixed = try {
            data["display_name_prefixed"].asString
        } catch (e: Exception) {
            "null"
        }

        val desc = try {
            data["public_description"].asString
        } catch (e: Exception) {
            "null"
        }
        val headerImage = try {
            data["header_img"].asString.replace("amp;", "")
        } catch (e: Exception) {
            "null"
        }
        var icon = try {
            data["icon_img"].asString.replace("amp;", "")
        } catch (e: Exception) {
            "null"
        }

        if (icon.isEmpty() || icon == "null") {
            icon = try {
                data["community_icon"].asString.replace("amp;", "")
            } catch (e: Exception) {
                "null"
            }
        }

        val banner = try {
            data["banner_background_image"].asString.replace("amp;", "")
        } catch (e: Exception) {
            "null"
        }

        val subscribers = try {
            data["subscribers"].asString
        } catch (e: Exception) {
            "null"
        }
        val fullDesc = try {
            data["description"].asString
        } catch (e: Exception) {
            "null"
        }

        return@withContext SubReddit(title, titlePrefixed, desc, headerImage, icon, banner, subscribers, fullDesc)
    } catch (e: Exception) {
        if (e !is SocketTimeoutException) {
            Log.e(TAG, "getSubredditInfo: ${e.stackTraceToString()}")
        }
        return@withContext SubReddit.getEmpty()
    }
}

suspend fun getGifMp4(permalink: String, client: OkHttpClient) = withContext(Dispatchers.IO) {
    var pair: Pair<String, String>

    try {
        val request = Request.Builder()
            .url("https://www.reddit.com$permalink/.json")
            .get()
            .build()

        val response = client.newCall(request).execute()
        val json = response.body?.string()
        val jsonObject = JsonParser.parseString(json).asJsonArray[0].asJsonObject
        val post = jsonObject["data"].asJsonObject["children"].asJsonArray[0].asJsonObject["data"].asJsonObject
        val gif = try {
            post["preview"]
                .asJsonObject["images"]
                .asJsonArray[0]
                .asJsonObject["variants"]
                .asJsonObject["gif"]
                .asJsonObject["source"]
                .asJsonObject["url"]
                .asString
                .replace("amp;", "")
        } catch (e: Exception) {
            "null"
        }
        val gifMP4 = try {
            post["preview"]
                .asJsonObject["images"]
                .asJsonArray[0]
                .asJsonObject["variants"]
                .asJsonObject["mp4"]
                .asJsonObject["source"]
                .asJsonObject["url"]
                .asString
                .replace("amp;", "")
        } catch (e: Exception) {
            "null"
        }

        pair = Pair(gif, gifMP4)
    } catch (e: Exception) {
        Log.e(TAG, "getGifMp4: ${e.stackTraceToString()}")
        pair = Pair("null", "null")
    }

    pair
}

fun runAfter(ms: Long, block: () -> Unit) {
    val handler = Handler(Looper.getMainLooper())
    handler.postDelayed(
        block,
        ms
    )
}

fun isOnline(context: Context): Boolean {
    val connectivityManager =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    val capabilities =
        connectivityManager.getNetworkCapabilities(connectivityManager.activeNetwork)
    if (capabilities != null) {
        when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> {
                Log.i("Internet", "NetworkCapabilities.TRANSPORT_CELLULAR")
                return true
            }

            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> {
                Log.i("Internet", "NetworkCapabilities.TRANSPORT_WIFI")
                return true
            }

            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> {
                Log.i("Internet", "NetworkCapabilities.TRANSPORT_ETHERNET")
                return true
            }
        }
    }
    return false
}

fun MutableList<Any>.placeAds() {
    val rList = mutableListOf<String>()
    for (e in this) {
        if (e is String) rList.add(e)
    }
    this.removeAll(rList)

    for (i in 0 until this.size) {
        if (i % 5 == 0 && i != 0) {
            this.add(i, "Ad")
        }
    }
}

fun getSubredditSort(sort: String): SubredditSort {
    return when (sort) {
        HOT -> SubredditSort.HOT
        NEW -> SubredditSort.NEW
        TOP -> SubredditSort.TOP
        RISING -> SubredditSort.RISING
        CONTROVERSIAL -> SubredditSort.CONTROVERSIAL
        else -> SubredditSort.HOT
    }
}

