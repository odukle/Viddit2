package com.odukle.viddit.fragments

import android.util.Log
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import com.odukle.viddit.adapters.SubredditAdapter
import com.odukle.viddit.models.SubReddit
import com.odukle.viddit.utils.CONTAINS_GIF
import com.odukle.viddit.utils.RICH_VIDEO
import com.odukle.viddit.utils.getSubredditInfo
import com.odukle.viddit.utils.ioScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import net.dean.jraw.RedditClient
import net.dean.jraw.models.Submission
import net.dean.jraw.models.SubredditSort
import net.dean.jraw.models.TimePeriod
import net.dean.jraw.models.UserHistorySort
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
        //TODO check internet
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
                //TODO handle failure
                Log.d(TAG, "populateRV: failed")
            }

            _isRefreshing.postValue(false)
        }
    }

    suspend fun getSubreddit(subredditName: String, client: OkHttpClient) {
        val sr = getSubredditInfo("r/$subredditName", client)
        _subreddit.postValue(sr)
    }
}