package com.odukle.viddit.fragments

import android.util.Log
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import com.google.gson.JsonArray
import com.google.gson.JsonParser
import com.odukle.viddit.MainActivity
import com.odukle.viddit.adapters.VideoAdapter
import com.odukle.viddit.utils.*
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import net.dean.jraw.RedditClient
import net.dean.jraw.models.Submission
import net.dean.jraw.models.SubredditSort
import net.dean.jraw.pagination.DefaultPaginator
import okhttp3.OkHttpClient
import okhttp3.Request

private const val TAG = "HomeViewModel"

class HomeViewModel : ViewModel() {

    private val _isRefreshing = MutableLiveData<Boolean>(false)
    val isRefreshing: LiveData<Boolean> = _isRefreshing
    private val _videosExhausted = MutableLiveData<Boolean>(false)
    val videosExhausted: LiveData<Boolean> = _videosExhausted
    private val _goToTop = MutableLiveData<Boolean>(false)
    val goToTop: LiveData<Boolean> = _goToTop
    private val _commentsArray = MutableLiveData<JsonArray?>(null)
    val commentsArray: LiveData<JsonArray?> = _commentsArray

    var job: Job? = null
    var pages: DefaultPaginator<Submission>? = null
    val adapter = VideoAdapter(mutableListOf())

    // After opening a subreddit fragment from main fragment and then opening Videos
    // from that subreddit and then pressing back button 2 times, the main fragment
    // will open the VideoAdapter with "tempList" at "tempPosition"
    val tempList = mutableListOf<Any>()
    var tempPosition = 0
    var tempPages: DefaultPaginator<Submission>? = null

    // when main fragment is called for a multi, onDestroy will save adapter list and position in below two variables
    val tempListMulti = mutableListOf<Any>()
    var tempPositionMulti = 0
    var tempPagesMulti: DefaultPaginator<Submission>? = null

    // when changing feed (Front Page/Popular) save adapter list and position in below two variables
    val tempListFront = mutableListOf<Any>()
    var tempPositionFront = 0
    var tempPageFront: DefaultPaginator<Submission>? = null
    val tempListPop = mutableListOf<Any>()
    var tempPositionPop = 0
    var tempPagesPop: DefaultPaginator<Submission>? = null

    //
    var adapterPosition = 0
    var oldSize = 0

    init {
        Log.d(TAG, "init: called")
    }

    suspend fun getPages(
        calledFor: Int = FOR_MAIN,
        reddit: RedditClient,
        subreddit: String = "",
        sorting: String = HOT,
        multi: String = "",
    ): DefaultPaginator<Submission> {
        val srSort = getSubredditSort(sorting)
        Log.d(TAG, "getPages: called for $multi")
        return when (calledFor) {
            FOR_MAIN -> reddit.frontPage().sorting(SubredditSort.HOT).limit(100).build()
            FOR_SUBREDDIT -> reddit.subreddit(subreddit).posts().sorting(srSort).limit(100).build()
            else -> reddit.me().multi(multi).posts().sorting(SubredditSort.HOT).limit(100).build()
        }
    }

    fun loadMoreData(pages: DefaultPaginator<Submission>, doShuffle: Boolean = false) {
        //TODO check internet
        Log.d(TAG, "loadMoreData: loading")
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

                    mainScope().launch {
                        adapter.vList.addAll(mList)
                        if (doShuffle) {
                            adapter.vList.shuffle()
                            adapter.notifyDataSetChanged()
                        }
                        adapter.vList.placeAds()
                        if (oldSize == 0) {
                            adapter.notifyDataSetChanged()
                            _goToTop.postValue(true)
                        } else adapter.notifyItemRangeInserted(oldSize, adapter.itemCount - oldSize)
                    }

                    if (mList.size < 15) {
                        loadMoreData(pages)
                        return@launch
                    }
                } else {
                    _videosExhausted.postValue(true)
                }
            } catch (e: Exception) {
                //TODO handle failure
                Log.d(TAG, "loadMoreData: failed")
            }

            _isRefreshing.postValue(false)
        }
    }

    fun getComments(permalink: String, client: OkHttpClient) {
        //TODO check Internet

        ioScope().launch {
            val request = Request.Builder()
                .url("https://www.reddit.com$permalink.json?raw_json=1")
                .get()
                .build()

            val response = client.newCall(request).execute()
            val json = response.body?.string()
            val jsonObject = JsonParser.parseString(json).asJsonArray[1].asJsonObject
            val cArray = jsonObject["data"].asJsonObject["children"].asJsonArray
            _commentsArray.postValue(cArray)
        }
    }

}