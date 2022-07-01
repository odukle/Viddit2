package com.odukle.viddit.utils

import android.graphics.Bitmap
import android.util.Log
import android.webkit.WebView
import android.webkit.WebViewClient
import com.odukle.viddit.App.Companion.accountHelper
import com.odukle.viddit.App.Companion.tokenStore
import com.odukle.viddit.BuildConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers.IO
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import net.dean.jraw.RedditClient
import net.dean.jraw.http.OkHttpNetworkAdapter
import net.dean.jraw.http.UserAgent
import net.dean.jraw.models.Submission
import net.dean.jraw.models.SubredditSort
import net.dean.jraw.oauth.StatefulAuthHelper
import net.dean.jraw.pagination.DefaultPaginator


private const val TAG = "RedditHelper"

suspend fun getSubmissionPages(reddit: RedditClient, title: String): DefaultPaginator<Submission> = withContext(IO) {
    val multi = reddit.me().multi(title)
    multi.posts().sorting(SubredditSort.HOT).limit(100).build()
}

class RedditHelper {

    private lateinit var adapter: OkHttpNetworkAdapter
    lateinit var authHelper: StatefulAuthHelper
    var reddit: RedditClient? = null

    fun init() {
        val userAgent = UserAgent("Android", BuildConfig.APPLICATION_ID, BuildConfig.VERSION_NAME, "odukle")
        adapter = OkHttpNetworkAdapter(userAgent)
        authHelper = accountHelper.switchToNewUser()
        val userLess = accountHelper.switchToUserless()
        try {
            if (tokenStore.usernames.isNotEmpty()) {
                reddit = accountHelper.switchToUser(tokenStore.usernames[0])
            }
        } catch (e: IllegalStateException) {
        }

//        reddit?.let { main.shortToast("logged in as ${it.authManager.currentUsername()}") } ?: main.shortToast("Browsing anonymously")
    }



}