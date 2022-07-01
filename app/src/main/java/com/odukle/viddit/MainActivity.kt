package com.odukle.viddit

import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.fragment.app.Fragment
import androidx.lifecycle.MutableLiveData
import com.google.android.exoplayer2.ExoPlayer
import com.google.android.exoplayer2.trackselection.DefaultTrackSelector
import com.google.android.gms.ads.MobileAds
import com.odukle.viddit.adapters.SubredditAdapter
import com.odukle.viddit.adapters.VideoAdapter
import com.odukle.viddit.fragments.FragmentCustomFeeds
import com.odukle.viddit.fragments.FragmentDiscover
import com.odukle.viddit.fragments.FragmentHome
import com.odukle.viddit.fragments.SubredditFragment
import com.odukle.viddit.utils.*
import kotlinx.android.synthetic.main.activity_main.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import net.dean.jraw.RedditClient
import net.dean.jraw.http.OkHttpNetworkAdapter
import net.dean.jraw.http.UserAgent
import net.dean.jraw.oauth.StatefulAuthHelper
import okhttp3.OkHttpClient

private const val TAG = "MainActivity"
var backstack = 0

class MainActivity : AppCompatActivity(),
    ExoPool,
    VideoAdapter.OnPlayerAcquired,
    FragmentHome.OnFragmentStateChanged,
    SubredditAdapter.OnOpenFragment,
    VideoAdapter.OnAdapterCallback,
    SubredditAdapter.OnLoadMoreDataSR {

    private lateinit var networkAdapter: OkHttpNetworkAdapter
    private lateinit var authHelper: StatefulAuthHelper
    var redditLive = MutableLiveData<RedditClient>()
    lateinit var reddit: RedditClient
    private var currentPlayer: ExoPlayer? = null
    val client = OkHttpClient()
    val playerList = mutableListOf<ExoPlayer>()

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "onCreate: called")
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        initReddit()
        MobileAds.initialize(this)
        toast = Toast(this)
        setUpBrowser()

        openFragment(FragmentHome.newInstance())
        bottom_navigation.setOnItemSelectedListener {
            when (it.itemId) {
                R.id.home -> {
                    if (getCurrentFragment() !is FragmentHome) {
                        openFragment(FragmentHome.newInstance())
                    }
                }
                R.id.discover -> {
                    openFragment(FragmentDiscover.newInstance())
                }
                R.id.custom_feed -> {
                    openFragment(FragmentCustomFeeds.newInstance())
                }
            }
            true
        }
    }

    fun openFragment(fragment: Fragment) {
        val tag = when (fragment) {
            is FragmentHome -> FragmentHome::class.simpleName
            is FragmentDiscover -> FragmentDiscover::class.simpleName
            is FragmentCustomFeeds -> FragmentCustomFeeds::class.simpleName
            is SubredditFragment -> SubredditFragment::class.simpleName
            else -> "default"
        }
        val ft = supportFragmentManager.beginTransaction()
        ft.replace(R.id.fragment_container, fragment)
        ft.addToBackStack("${++backstack}")
        ft.commit()
    }

    private fun setUpBrowser() {
        val ws = browser.settings
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ws.forceDark = WebSettings.FORCE_DARK_ON
        }
        ws.cacheMode = WebSettings.LOAD_NO_CACHE
    }

    private fun initReddit() {
        ioScope().launch {
            val userAgent = UserAgent("Android", BuildConfig.APPLICATION_ID, BuildConfig.VERSION_NAME, "odukle")
            networkAdapter = OkHttpNetworkAdapter(userAgent)
            authHelper = App.accountHelper.switchToNewUser()
            try {
                if (App.tokenStore.usernames.isNotEmpty()) {
                    reddit = App.accountHelper.switchToUser(App.tokenStore.usernames[0])
                    Log.d(TAG, "initReddit user: ${reddit.me().username}")
                } else {
                    reddit = App.accountHelper.switchToUserless()
                }

                redditLive.postValue(reddit)
            } catch (e: IllegalStateException) {
                Log.e(TAG, "initReddit: ${e.stackTraceToString()}")
            }
        }

    }

    fun startSignIn() {

        val authUrl = authHelper.getAuthorizationUrl(
            true, true,
            "identity", "edit", "history", "read", "save", "submit", "subscribe", "vote"
        )

        browser_layout.show()
        browser.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                loader.show()
                if (url != null && authHelper.isFinalRedirectUrl(url)) {
                    browser.stopLoading()
                    CoroutineScope(Dispatchers.IO).launch {
                        Log.d(TAG, "onPageStarted: $url")
                        reddit = authHelper.onUserChallenge(url)
                        reddit.autoRenew = true
                        reddit.authManager.refreshToken?.let {
                            reddit.authManager.current?.let { it1 -> App.tokenStore.storeLatest(reddit.authManager.currentUsername(), it1) }
                            App.tokenStore.storeRefreshToken(reddit.authManager.currentUsername(), it)
                        }
                        mainScope().launch {
                            shortToast(this@MainActivity, "Logged in as " + reddit.me().username)
                            clearCookies()
                            browser_layout.hide()
                            delay(200)
                            triggerRebirth()
                        }
                    }
                }
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                loader.hide()
                super.onPageFinished(view, url)
            }
        }

        browser.loadUrl(authUrl)
    }

    private fun clearCookies() {
        CookieManager.getInstance().removeAllCookies(null)
        CookieManager.getInstance().flush()
    }

    fun triggerRebirth() {
        val packageManager = packageManager
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val componentName = intent!!.component
        val mainIntent = Intent.makeRestartActivityTask(componentName)
        startActivity(mainIntent)
        Runtime.getRuntime().exit(0)
    }


    companion object {
        lateinit var toast: Toast
    }

    override fun acquire(): ExoPlayer {
        val trackSelector = DefaultTrackSelector(this).apply {
            setParameters(buildUponParameters().setMaxVideoSize(1280, 720))
        }
        val player = ExoPlayer.Builder(this)
            .setTrackSelector(trackSelector)
            .build()

        playerList.add(player)
        return player
    }

    override fun release(player: ExoPlayer) {
        playerList.remove(player)
        player.release()
        if (playerList.size > 4) {
            val rl = mutableListOf<ExoPlayer>()
            playerList.forEach {
                if (!(it.isLoading || it.isPlaying)) {
                    it.release()
                    rl.add(it)
                }
            }
            playerList.removeAll(rl)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
    }

    override fun onPause() {
        currentPlayer?.pause()
        super.onPause()
    }

    override fun onResume() {
        currentPlayer?.play()
        super.onResume()
    }

    fun getCurrentFragment(): Fragment? = supportFragmentManager.findFragmentById(R.id.fragment_container)

    override fun onBackPressed() {
        if (supportFragmentManager.backStackEntryCount == 1) {
            moveTaskToBack(false)
        } else super.onBackPressed()
    }

    override fun onPlayerAcquired(player: ExoPlayer) {
        currentPlayer = player
    }

    override fun pauseCurrentPlayer() {
        currentPlayer?.pause()
    }

    override fun onOpenFragment(fragment: Fragment) {
        openFragment(fragment)
    }

    override fun onLoadMoreData() {
        val fh = getCurrentFragment() as FragmentHome
        fh.onLoadMoreData()
    }

    override fun onLoadMoreDataSR() {
        val srf = getCurrentFragment() as SubredditFragment
        srf.onLoadMoreDataSR()
    }
}