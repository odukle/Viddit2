package com.odukle.vidred.fragments

import android.util.Log
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import com.google.gson.JsonParser
import com.odukle.vidred.adapters.SubredditAdapter
import com.odukle.vidred.models.MultiReddit
import com.odukle.vidred.models.SubReddit
import com.odukle.vidred.utils.CONTAINS_GIF
import com.odukle.vidred.utils.RICH_VIDEO
import com.odukle.vidred.utils.getSubredditInfo
import com.odukle.vidred.utils.ioScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import net.dean.jraw.Endpoint
import net.dean.jraw.JrawUtils
import net.dean.jraw.RedditClient
import net.dean.jraw.http.HttpRequest
import net.dean.jraw.models.*
import net.dean.jraw.pagination.DefaultPaginator
import net.dean.jraw.references.AbstractReference
import net.dean.jraw.references.OtherUserReference
import net.dean.jraw.references.SubredditReference
import okhttp3.OkHttpClient

private const val TAG = "SubredditViewModel"

class SubredditViewModel : ViewModel() {

    private val _isRefreshing = MutableLiveData<Boolean>(false)
    val isRefreshing: LiveData<Boolean> = _isRefreshing
    private val _videosExhausted = MutableLiveData<Boolean>(false)
    val videosExhausted: LiveData<Boolean> = _videosExhausted
    private val _dataLoaded = MutableLiveData<Boolean>(false)
    val dataLoaded: LiveData<Boolean> = _dataLoaded
    private val _subredditRef = MutableLiveData<AbstractReference?>(null)
    val subredditRef: LiveData<AbstractReference?> = _subredditRef
    private val _subreddit = MutableLiveData<SubReddit>(SubReddit.getEmpty())
    val subreddit: LiveData<SubReddit> = _subreddit
    //

    private val _cfJson: MutableLiveData<String> = MutableLiveData("")
    val cfJson: LiveData<String> = _cfJson
    private val _subredditAdded = MutableLiveData<Boolean>(false)
    val subredditAdded: LiveData<Boolean> = _subredditAdded
    private val _multiReddit = MutableLiveData<MultiReddit?>(null)
    val multiReddit: LiveData<MultiReddit?> = _multiReddit

    var oldSize = 0
    val pagesLive = MutableLiveData<DefaultPaginator<Submission>?>(null)
    val adapter = SubredditAdapter(mutableListOf())

    var job: Job? = null

    fun getSubredditRef(reddit: RedditClient, subredditName: String, isUser: Boolean = false) {
        Log.d(TAG, "getSubredditRef: $subredditName")
        val srf = if (!isUser) reddit.subreddit(subredditName) else reddit.user(subredditName)
        _subredditRef.postValue(srf)
    }

    fun getSRPages(
        srf: AbstractReference,
        sort: SubredditSort = SubredditSort.HOT,
        isUser: Boolean = false,
        timePeriod: TimePeriod = TimePeriod.ALL
    ) {
        _videosExhausted.postValue(false)
        if (!isUser) {
            srf as SubredditReference
            pagesLive.postValue(
                srf.posts()
                    .sorting(sort)
                    .timePeriod(timePeriod)
                    .limit(100)
                    .build()
            )
        } else {
            srf as OtherUserReference
            pagesLive.postValue(
                srf.history("submitted")
                    .sorting(getUserHistorySort(sort))
                    .timePeriod(timePeriod)
                    .limit(100)
                    .build() as DefaultPaginator<Submission>
            )
        }
    }

    private fun getUserHistorySort(sort: SubredditSort): UserHistorySort {
        return when (sort) {
            SubredditSort.HOT -> UserHistorySort.HOT
            SubredditSort.CONTROVERSIAL -> UserHistorySort.CONTROVERSIAL
            SubredditSort.RISING -> UserHistorySort.HOT
            SubredditSort.TOP -> UserHistorySort.TOP
            SubredditSort.BEST -> UserHistorySort.HOT
            SubredditSort.NEW -> UserHistorySort.NEW
        }
    }

    fun loadMoreDataSR(pages: DefaultPaginator<Submission>) {
        // Can check for internet
        Log.d(TAG, "populateRV: loading")
        job = ioScope().launch {
            _isRefreshing.postValue(true)
            oldSize = adapter.vList.size
            try {
                val mList = mutableListOf<Submission>()
                if (pages.iterator().hasNext()) {
                    pages.iterator().next().forEach { post ->
                        val isGif = post.preview?.images?.get(0)?.source?.url?.contains(CONTAINS_GIF) ?: false
                        if ((post.embeddedMedia?.redditVideo?.hlsUrl != null || isGif) && post.postHint != RICH_VIDEO) {
                            mList.add(post)
                        }
                    }

                    adapter.vList.addAll(mList)
                    if (oldSize == 0) _dataLoaded.postValue(true)
                    adapter.notifyItemRangeInserted(oldSize, adapter.itemCount - oldSize)

                    if (mList.size < 15) {
                        loadMoreDataSR(pages)
                        return@launch
                    }

                } else {
                    _videosExhausted.postValue(true)
                }
            } catch (e: Exception) {
                // Can handle failure
                Log.d(TAG, "populateRV: failed")
            }

            _isRefreshing.postValue(false)
        }
    }

    suspend fun getSubreddit(subredditName: String, client: OkHttpClient) {
        val sr = getSubredditInfo("r/$subredditName", client)
        _subreddit.postValue(sr)
    }

    fun getCustomFeeds(reddit: RedditClient) {

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