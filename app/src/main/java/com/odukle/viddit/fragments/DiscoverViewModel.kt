package com.odukle.viddit.fragments

import android.util.Log
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import com.google.gson.JsonParser
import com.odukle.viddit.models.MultiReddit
import com.odukle.viddit.utils.ioScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import net.dean.jraw.Endpoint
import net.dean.jraw.JrawUtils
import net.dean.jraw.RedditClient
import net.dean.jraw.http.HttpRequest
import net.dean.jraw.models.MultiredditPatch
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.SocketTimeoutException

private const val TAG = "DiscoverViewModel"

class DiscoverViewModel : ViewModel() {

    private val _rList: MutableLiveData<MutableList<Pair<String, String>>> = MutableLiveData(mutableListOf())
    val rList: MutableLiveData<MutableList<Pair<String, String>>> = _rList
    private val _cfJson: MutableLiveData<String> = MutableLiveData("")
    val cfJson: LiveData<String> = _cfJson
    private val _subredditAdded = MutableLiveData<Boolean>(false)
    val subredditAdded: LiveData<Boolean> = _subredditAdded
    private val _multiReddit = MutableLiveData<MultiReddit?>(null)
    val multiReddit: LiveData<MultiReddit?> = _multiReddit

    @Suppress("BlockingMethodInNonBlockingContext")
    suspend fun getTopSubreddits(client: OkHttpClient) {
        val list = mutableListOf<Pair<String, String>>()
        //TODO check for internet

        try {
            val request = Request.Builder()
                .url("https://parsehub.com/api/v2/projects/tFUsBtX0e0CL/last_ready_run/data?api_key=t0GcPvB4jaai&format=json")
                .get()
                .build()

            val response = client.newCall(request).execute()
            val json = response.body?.string()
            val jsonObject = JsonParser.parseString(json).asJsonObject
            val subreddits = jsonObject["growing"].asJsonArray
            subreddits.forEach {
                val image = try {
                    it.asJsonObject["image"].asString.replace("amp;", "")
                } catch (e: java.lang.Exception) {
                    ""
                }
                val namePrefixed = it.asJsonObject["url"].asString.replace("https://www.reddit.com/", "").removeSuffix("/")
                val pair = Pair(image, namePrefixed)
                list.add(pair)
            }

            _rList.postValue(list)
        } catch (e: Exception) {
            if (e is SocketTimeoutException) {
                //TODO
            } else {
                Log.e(TAG, "getTopSubreddits: ${e.stackTraceToString()}")
            }
        }
    }

    @Suppress("BlockingMethodInNonBlockingContext")
    suspend fun searchSubreddits(query: String, nsfwAllowed: Boolean, client: OkHttpClient) {
        Log.d(TAG, "getSubreddits: called")
        val list = mutableListOf<Pair<String, String>>()
        val strNsfw = if (nsfwAllowed) "&restrict_sr=true&include_over_18=on" else ""

        //TODO check internet

        try {
            val request = Request.Builder()
                .url("https://www.reddit.com/subreddits/search.json?q=$query&$strNsfw")
                .get()
                .build()

            val response = client.newCall(request).execute()
            val json = response.body?.string()
            val jsonObject = JsonParser.parseString(json).asJsonObject
            val data = jsonObject["data"].asJsonObject
            val subreddits = data["children"].asJsonArray
            subreddits.forEach {
                val subreddit = it.asJsonObject["data"].asJsonObject
                var image = try {
                    subreddit["icon_img"].asString.replace("amp;", "")
                } catch (e: Exception) {
                    "null"
                }

                if (image.isEmpty() || image == "null") {
                    image = try {
                        subreddit["community_icon"].asString.replace("amp;", "")
                    } catch (e: Exception) {
                        "null"
                    }
                }
                val namePrefixed = subreddit["display_name_prefixed"].asString

                list.add(Pair(image, namePrefixed))
            }

            _rList.postValue(list)
        } catch (e: Exception) {
            if (e is SocketTimeoutException) {
                //TODO
            } else {
                Log.e(TAG, "getSubreddits: ${e.stackTraceToString()}")
            }
        }
    }

    fun getCustomFeeds(reddit: RedditClient) {

        //TODO check for internet

        ioScope().launch {
            val request = HttpRequest.Builder()
                .secure(true)
                .host("oauth.reddit.com")
                .endpoint(Endpoint.GET_MULTI_MINE)
                .header("Authorization", "bearer ${reddit.authManager.accessToken}")
                .build()

            val res = reddit.request(request)

            _cfJson.postValue(res.body)
        }
    }

    fun addSubRedditToCf(reddit: RedditClient, name: String, subredditName: String) {
        //TODO check for internet
        ioScope().launch {
            reddit.me().multi(name).addSubreddit(subredditName)
            _subredditAdded.postValue(true)
        }
    }

    fun addMulti(displayName: String, reddit: RedditClient) {
        val name = displayName.replace(" ", "")
        val patch = MultiredditPatch.Builder()
            .iconName("png")
            .displayName(displayName)
            .build()
        ioScope().launch {
            try {
                reddit.me().createMulti(name, patch)
            } catch (e: Exception) {
            }

            val json = getMultiRedditAbout(reddit, name)
            val feed = JsonParser.parseString(json).asJsonObject
            val multi = MultiReddit(
                name,
                displayName,
                feed["data"].asJsonObject["icon_url"].asString,
                feed["data"].asJsonObject["subreddits"].asJsonArray.map { it.asJsonObject["name"].asString }.toMutableList()
            )

            _multiReddit.postValue(multi)
        }
    }

    private suspend fun getMultiRedditAbout(reddit: RedditClient, title: String) = withContext(Dispatchers.IO) {

        //TODO check for internet

        val multiPath = "user/${JrawUtils.urlEncode(reddit.me().username)}/m/${JrawUtils.urlEncode(title)}"
        val request = HttpRequest.Builder()
            .secure(true)
            .host("oauth.reddit.com")
            .endpoint(Endpoint.GET_MULTI_MULTIPATH, multiPath)
            .header("Authorization", "bearer ${reddit.authManager.accessToken}")
            .build()

        val res = reddit.request(request)

        return@withContext res.body
    }
}