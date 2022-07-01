package com.odukle.viddit.fragments

import android.util.Log
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import com.odukle.viddit.adapters.SubredditAdapter
import com.odukle.viddit.models.SubReddit
import com.odukle.viddit.utils.getSubredditInfo
import com.odukle.viddit.utils.ioScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import net.dean.jraw.RedditClient
import net.dean.jraw.models.Submission
import net.dean.jraw.models.SubredditSort
import net.dean.jraw.pagination.DefaultPaginator
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
    private val _subredditRef = MutableLiveData<SubredditReference?>(null)
    val subredditRef: LiveData<SubredditReference?> = _subredditRef
    private val _subreddit = MutableLiveData<SubReddit>(SubReddit.getEmpty())
    val subreddit: LiveData<SubReddit> = _subreddit

    val adapter = SubredditAdapter(mutableListOf())
    var oldSize = 0
    val pages = MutableLiveData<DefaultPaginator<Submission>?>(null)

    //    val pages: LiveData<DefaultPaginator<Submission>?> = _pages
    //    var pages: DefaultPaginator<Submission>? = null
    var job: Job? = null

    fun getSubredditRef(reddit: RedditClient, subredditName: String) {
        Log.d(TAG, "getSubredditRef: $subredditName")
        val srf = reddit.subreddit(subredditName)
        _subredditRef.postValue(srf)
    }

    fun getSRPages(srf: SubredditReference, sort: SubredditSort = SubredditSort.HOT) {
        _videosExhausted.postValue(false)
        pages.postValue(srf.posts().sorting(sort).limit(100).build())
    }

    fun loadMoreDataSR(pages: DefaultPaginator<Submission>, callCount: Int = 0) {
        //TODO check internet
        Log.d(TAG, "populateRV: loading")
        job = ioScope().launch {
            _isRefreshing.postValue(true)
            oldSize = adapter.vList.size
            try {
                val mList = mutableListOf<Submission>()
                if (pages.iterator().hasNext()) {
                    pages.iterator().next().forEach { post ->
                        val isGif = post.preview?.images?.get(0)?.source?.url?.contains(".gif?") ?: false
                        if (post.embeddedMedia?.redditVideo?.hlsUrl != null || isGif) {
                            mList.add(post)
                        }
                    }
                    if (mList.size < 15) {
                        loadMoreDataSR(pages)
                        return@launch
                    }
                    adapter.vList.addAll(mList)
                    if (oldSize == 0) _dataLoaded.postValue(true)
                    adapter.notifyItemRangeInserted(oldSize, adapter.itemCount - oldSize)
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