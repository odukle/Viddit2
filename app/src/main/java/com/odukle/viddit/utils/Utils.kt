@file:Suppress("BlockingMethodInNonBlockingContext")

package com.odukle.viddit.utils

import android.animation.ObjectAnimator
import android.app.Activity
import android.app.ProgressDialog.show
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.text.InputFilter
import android.util.Log
import android.view.View
import android.widget.Toast
import androidx.fragment.app.Fragment
import com.google.gson.JsonParser
import com.odukle.viddit.MainActivity
import com.odukle.viddit.MainActivity.Companion.toast
import com.odukle.viddit.R
import com.odukle.viddit.models.AboutPost
import com.odukle.viddit.models.SubReddit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Dispatchers.IO
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import net.dean.jraw.models.Submission
import net.dean.jraw.models.SubredditSort
import okhttp3.OkHttpClient
import okhttp3.Request
import java.math.RoundingMode
import java.net.SocketTimeoutException
import java.text.DecimalFormat
import java.util.*
import kotlin.math.roundToInt

const val USER_LESS = "<userless>"
private const val TAG = "Utils"
const val SUBREDDIT_FRAGMENT = "subredditFragment"
const val SUBREDDIT_NAME = "subredditName"
const val SORTING = "sorting"
const val MULTI_NAME = "multiName"
const val IS_USER = "isUser"
const val CALLED_FOR = "loadfp"
const val JSON_LIST = "jList"
const val ADAPTER_POSITION = "adapterPos"
const val MY_PREFS = "myPrefs"
const val NSFW = "NSFW"
const val FRONT_PAGE = "frontPage"
const val POPULAR = "popular"
const val AD_DIST = 5

// sorting
const val HOT = "hot"
const val NEW = "new"
const val TOP = "top"
const val RISING = "rising"
const val CONTROVERSIAL = "controversial"

//
const val FOR_MAIN = 1
const val FOR_SUBREDDIT = 2
const val FOR_MULTI = 3

//
const val RICH_VIDEO = "rich:video"
const val HOSTED_VIDEO = "hosted:video"
const val CONTAINS_GIF = ".gif?"


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

fun showNoInternetToast(context: Context) {
    context as Activity
    context.runOnUiThread {
        toast.cancel()
        toast = Toast.makeText(context, "No internet 😔", Toast.LENGTH_SHORT).apply { show() }
    }
}

fun Long.toTimeAgo(): String {
    return when (val hr = ((Calendar.getInstance().timeInMillis - this) / 3600000L)) {
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

suspend fun getSubredditInfo(
    subreddit: String,
    client: OkHttpClient,
    isUser: Boolean = false
): SubReddit = withContext(Dispatchers.IO) {

    try {
        val request = Request.Builder()
            .url("https://www.reddit.com/$subreddit/about.json")
            .get()
            .build()

        val response = client.newCall(request).execute()
        val json = response.body?.string()
        val jsonObject = JsonParser.parseString(json).asJsonObject
        val data =
            if (!isUser) jsonObject["data"].asJsonObject else jsonObject["data"].asJsonObject["subreddit"].asJsonObject
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

        return@withContext SubReddit(
            title,
            titlePrefixed,
            desc,
            headerImage,
            icon,
            banner,
            subscribers,
            fullDesc
        )
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
        val post =
            jsonObject["data"].asJsonObject["children"].asJsonArray[0].asJsonObject["data"].asJsonObject
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

fun tryThreeTimes(block: () -> Unit) {
    for (i in 0..3) {
        try {
            run(block)
            break
        } catch (e: Exception) {
            Log.e(TAG, "tryThreeTimes: ${e.message}")
            if (i < 3) run(block)
        }
    }
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

fun placeAds(list: MutableList<Any>): MutableList<Any> {
    val rList = mutableListOf<String>()
    for (e in list) {
        if (e is String) rList.add(e)
    }
    list.removeAll(rList)

    for (i in 0 until list.size) {
        if (i % AD_DIST == 0 && i != 0) {
            list.add(i, "Ad")
        }
    }

    return list
}

fun MutableList<Any>.placeAds() {
    val rList = mutableListOf<String>()
    for (e in this) {
        if (e is String) rList.add(e)
    }
    this.removeAll(rList)

    for (i in 0 until this.size) {
        if (i % AD_DIST == 0 && i != 0) {
            this.add(i, "Ad")
        }
    }
}

fun getSubredditSort(sort: String): SubredditSort {
    val order = when (sort) {
        HOT -> SubredditSort.HOT
        NEW -> SubredditSort.NEW
        TOP -> SubredditSort.TOP
        RISING -> SubredditSort.RISING
        CONTROVERSIAL -> SubredditSort.CONTROVERSIAL
        else -> SubredditSort.HOT
    }

    return order
}

fun nsfwAllowed(context: Context): Boolean {
    val sharedPreferences = context.getSharedPreferences(MY_PREFS, Context.MODE_PRIVATE)
    return sharedPreferences.getBoolean(NSFW, false)
}

fun doNotAllowNSFW(context: Context) {
    val sharedPreferences = context.getSharedPreferences(MY_PREFS, Context.MODE_PRIVATE)
    return sharedPreferences.edit().putBoolean(NSFW, false).apply()
}

fun allowNSFW(context: Context) {
    val sharedPreferences = context.getSharedPreferences(MY_PREFS, Context.MODE_PRIVATE)
    sharedPreferences.edit().putBoolean(NSFW, true).apply()
}

fun View.bounce() {
    ObjectAnimator.ofFloat(this, "scaleX", 1F, 0.7F, 1F).setDuration(500).start()
    ObjectAnimator.ofFloat(this, "scaleY", 1F, 0.7F, 1F).setDuration(500).start()
}

const val blockCharacterSet = "~`!@#$%^&*()_-+=|\\}]{[:;'\"?/>.<,₹" //Special characters to block
val filter = InputFilter { source, _, _, _, _, _ ->
    if (source != null && blockCharacterSet.contains("" + source)) {
        ""
    } else null
}

fun getCurrentFragment(mainActivity: MainActivity): Fragment? =
    mainActivity.supportFragmentManager.findFragmentById(R.id.fragment_container)

fun MutableList<Submission>.getIndexAdjustedForAds(position: Int): Int {
    val video = this[position]
    val list = this.toList() as MutableList<Any>
    for (i in 0 until list.size) {
        if (i != 0 && i % AD_DIST == 0) {
            list.add(i, "Ad")
        }
    }

    return list.indexOf(video)
}

suspend fun getAboutPost(link: String, activity: MainActivity): AboutPost = withContext(IO) {

    if (!isOnline(activity)) {
        mainScope().launch {
            shortToast(activity, "No internet 😔")
        }
    }

    try {
        val uri = "$link.json?raw_json=1"
        val part1 = uri.substring(0, uri.indexOf("?") + 1)
        val part2 = uri.substring(uri.lastIndexOf("?") + 1)
        val url = Uri.parse("${part1.replace("?", ".json?")}$part2")
        Log.d(TAG, "getAboutPost: $url")
        val request = Request.Builder()
            .url(url.toString())
            .get()
            .build()

        val response = activity.client.newCall(request).execute()
        val json = response.body?.string()
        val array = JsonParser.parseString(json).asJsonArray
        val post = array[0]
            .asJsonObject["data"]
            .asJsonObject["children"]
            .asJsonArray[0]
            .asJsonObject["data"]
            .asJsonObject

        val title = try {
            post["title"].asString
        } catch (e: Exception) {
            "null"
        }

        val name = try {
            post["name"].asString
        } catch (e: Exception) {
            "null"
        }

        val subreddit = try {
            post["subreddit_name_prefixed"].asString
        } catch (e: Exception) {
            "null"
        }

        val image = try {
            post["preview"]
                .asJsonObject["images"]
                .asJsonArray[0]
                .asJsonObject["source"]
                .asJsonObject["url"]
                .asString
                .replace("amp;", "")
        } catch (e: Exception) {
            "null"
        }

        val videoDownloadUrl = try {
            post["media"]
                .asJsonObject["reddit_video"]
                .asJsonObject["fallback_url"]
                .asString.replace("amp;", "")
        } catch (e: Exception) {
            "null"
        }

        val gifmp4 = try {
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

        val permalink = try {
            "https://www.reddit.com/" + post["permalink"].asString
        } catch (e: Exception) {
            "null"
        }

        if (gifmp4 != "null") {
            return@withContext AboutPost(title, name, subreddit, image, gifmp4, permalink)
        } else if (videoDownloadUrl != "null") {
            return@withContext AboutPost(title, name, subreddit, image, videoDownloadUrl, permalink)
        } else {
            return@withContext AboutPost(title, name, subreddit, image, image, permalink)
        }

    } catch (e: Exception) {
        throw e
    }
}

fun String.removeSpecialChars(): String {
    var str = this
    blockCharacterSet.forEach {
        str = str.replace("$it", "")
    }

    return str
}

suspend fun hasAudio(link: String, activity: MainActivity) = withContext(IO) {

    if (!isOnline(activity)) {
        mainScope().launch {
            shortToast(activity, "No internet 😔")
        }
        return@withContext false
    }

    val url = Uri.parse("https://redditsave.com/info?url=$link")
    Log.d(TAG, "hasAudio: $url")
    val request = Request.Builder()
        .url(url.toString())
        .get()
        .build()

    val response = activity.client.newCall(request).execute()
    val body = response.body?.string()

    !(body?.contains("audio_url=false") ?: false)
}

fun truncateNumber(floatNumber: Float): String {
    val thousand = 1000
    val lac = 100000
    val million = 1000000
    val number = floatNumber.roundToInt()
    val df = DecimalFormat("#.#")
    df.roundingMode = RoundingMode.DOWN
    if (number in thousand until million) {
        val fraction = calculateFraction(number, thousand)
        return df.format(fraction) + "k"
    }
    return number.toString()
}

fun calculateFraction(number: Int, divisor: Int): Float {
    val truncate = (number * 10 + divisor / 2) / divisor
    return truncate.toFloat() * 0.10f
}





