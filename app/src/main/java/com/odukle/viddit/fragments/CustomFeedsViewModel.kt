package com.odukle.viddit.fragments

import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import com.google.gson.JsonParser
import com.odukle.viddit.models.MultiReddit
import com.odukle.viddit.utils.getSubredditInfo
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

class CustomFeedsViewModel : ViewModel() {

    private val _cfJson: MutableLiveData<String> = MutableLiveData("")
    val cfJson: LiveData<String> = _cfJson
    private val _multiReddit = MutableLiveData<MultiReddit?>(null)
    val multiReddit: LiveData<MultiReddit?> = _multiReddit
    private val _rList = MutableLiveData<MutableList<Pair<String, String>>>(mutableListOf())
    val rList: LiveData<MutableList<Pair<String, String>>> = _rList
    private val _showProgress: MutableLiveData<Boolean> = MutableLiveData(true)
    val showProgress: LiveData<Boolean> = _showProgress

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

    fun loadSubreddits(multiReddit: MultiReddit, client: OkHttpClient) {
        val list = mutableListOf<Pair<String, String>>()
        _showProgress.postValue(true)
        ioScope().launch {
            multiReddit.subreddits.forEach {
                val subreddit = getSubredditInfo("r/$it", client)
                val icon = subreddit.icon
                val name = subreddit.titlePrefixed
                list.add(Pair(icon, name))
            }

            _rList.postValue(list)
            _showProgress.postValue(false)
        }
    }
}