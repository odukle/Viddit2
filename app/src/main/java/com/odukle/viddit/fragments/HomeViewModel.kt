package com.odukle.viddit.fragments

import android.util.Log
import androidx.core.content.ContentProviderCompat.requireContext
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import com.odukle.viddit.MainActivity
import com.odukle.viddit.adapters.VideoAdapter
import com.odukle.viddit.utils.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import net.dean.jraw.RedditClient
import net.dean.jraw.models.Listing
import net.dean.jraw.models.Submission
import net.dean.jraw.models.Subreddit
import net.dean.jraw.models.SubredditSort
import net.dean.jraw.pagination.DefaultPaginator

private const val TAG = "HomeViewModel"

class HomeViewModel : ViewModel() {

    private val _isRefreshing = MutableLiveData<Boolean>(false)
    val isRefreshing: LiveData<Boolean> = _isRefreshing
    private val _videosExhausted = MutableLiveData<Boolean>(false)
    val videosExhausted: LiveData<Boolean> = _videosExhausted

    var job: Job? = null
    var pages: DefaultPaginator<Submission>? = null
    val adapter = VideoAdapter(mutableListOf())
    val tempList = mutableListOf<Any>()
    var adapterPosition = 0
    var tempPosition = 0
    var oldSize = 0

    init {
        Log.d(TAG, "init: called")
    }

    suspend fun getPages(
        reddit: RedditClient,
        subreddit: String,
        sorting: String
    ): DefaultPaginator<Submission> {
        val srSort = getSubredditSort(sorting)
        Log.d(TAG, "getPages: for $subreddit")
        return if (subreddit.isEmpty()) reddit.frontPage().sorting(SubredditSort.HOT).limit(100).build()
        else reddit.subreddit(subreddit).posts().sorting(srSort).limit(100).build()
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
                        val isGif = post.preview?.images?.get(0)?.source?.url?.contains(".gif?") ?: false
                        if (post.embeddedMedia?.redditVideo?.hlsUrl != null || isGif) {
                            mList.add(post)
                        }
                    }
                    if (mList.size < 15) {
                        loadMoreData(pages)
                        return@launch
                    }
                    Log.d(TAG, "loadMoreData: size -> ${mList.size}")
                    mList.shuffle()
                    mainScope().launch {
                        adapter.vList.addAll(mList)
                        adapter.vList.placeAds()
                        if (doShuffle) adapter.notifyDataSetChanged()
                        else adapter.notifyItemRangeInserted(oldSize, adapter.itemCount - oldSize)
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

}