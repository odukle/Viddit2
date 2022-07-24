package com.odukle.viddit

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import androidx.lifecycle.MutableLiveData
import com.bumptech.glide.Glide
import com.google.android.exoplayer2.ExoPlayer
import com.google.android.exoplayer2.trackselection.DefaultTrackSelector
import com.google.android.gms.ads.MobileAds
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.odukle.viddit.adapters.SubredditAdapter
import com.odukle.viddit.adapters.VideoAdapter
import com.odukle.viddit.fragments.*
import com.odukle.viddit.interfaces.OpenFragment
import com.odukle.viddit.models.AboutPost
import com.odukle.viddit.utils.*
import kotlinx.android.synthetic.main.activity_main.*
import kotlinx.android.synthetic.main.bottom_sheet_download.view.*
import kotlinx.android.synthetic.main.item_view_video.view.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import net.dean.jraw.RedditClient
import net.dean.jraw.android.BuildConfig
import net.dean.jraw.http.OkHttpNetworkAdapter
import net.dean.jraw.http.UserAgent
import net.dean.jraw.models.Submission
import net.dean.jraw.oauth.StatefulAuthHelper
import okhttp3.OkHttpClient

private const val TAG = "MainActivity"
var backstack = 0

class MainActivity : AppCompatActivity(),
    ExoPool,
    VideoAdapter.OnPlayerAcquired,
    FragmentHome.OnFragmentStateChanged,
    OpenFragment,
    VideoAdapter.OnCallback,
    SubredditAdapter.OnLoadMoreDataSR {

    private var downloadedUri: Uri? = null
    var tempPost: Submission? = null
    var tempHolder: VideoAdapter.VideoViewHolder? = null
    var playOnMute = false
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
                    if (bottom_navigation.selectedItemId != R.id.home) {
                        openFragment(FragmentHome.newInstance())
                    }
                }
                R.id.discover -> {
                    if (getCurrentFragment(this) !is FragmentDiscover) {
                        openFragment(FragmentDiscover.newInstance())
                    }
                }
                R.id.custom_feed -> {
                    if (getCurrentFragment(this) !is FragmentCustomFeeds) {
                        openFragment(FragmentCustomFeeds.newInstance())
                    }
                }
                R.id.user -> {
                    if (getCurrentFragment(this) !is UserFragment) {
                        openFragment(UserFragment.newInstance())
                    }
                }
            }
            true
        }
    }

    private fun openFragment(fragment: Fragment) {
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
                    if (reddit.authManager.currentUsername() == USER_LESS) {
                        shortToast(this@MainActivity, "Browsing Anonymously")
                    } else {
                        shortToast(this@MainActivity, "Signed in as ${reddit.authManager.currentUsername()}")
                    }
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
                            reddit.authManager.current?.let { it1 ->
                                App.tokenStore.clear()
                                App.tokenStore.storeLatest(reddit.authManager.currentUsername(), it1)
                            }
                            App.tokenStore.storeRefreshToken(reddit.authManager.currentUsername(), it)
                        }
                        mainScope().launch {
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

    override fun onNewIntent(intent: Intent?) {
        if (intent != null) {
            if (intent.action == Intent.ACTION_SEND) {
                handleIntent(intent)
            }
        }
        super.onNewIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        val link = intent.getStringExtra(Intent.EXTRA_TEXT)
        if (link != null) {
            if (link.contains("reddit.com")) {
                val dialog = BottomSheetDialog(this)
                val view = LayoutInflater.from(this).inflate(R.layout.bottom_sheet_download, null, false)
                dialog.setContentView(view)
                dialog.show()
                try {
                    view.apply {
                        ioScope().launch {
                            val post = getAboutPost(link, this@MainActivity)
                            val subreddit = getSubredditInfo(post.subreddit, client)
                            mainScope().launch {
                                tv_title_bsd.text = post.title
                                Glide.with(this@apply).load(post.image).centerCrop().into(iv_thumb_bsd)
                                chip_subreddit_bsd.text = "Go to ${post.subreddit}"
                                onStartDownloading(null, null, post, this@apply)

                                chip_subreddit_bsd.setOnClickListener {
                                    if (isOnline(this@MainActivity)) {
                                        shortToast(this@MainActivity, "No internet 😔")
                                        return@setOnClickListener
                                    }

                                    dialog.dismiss()
                                    mainScope().launch {
                                        val fragment = SubredditFragment.newInstance(subreddit.title)
                                        openFragment(fragment)
                                    }
                                }

                                iv_play_bsd.setOnClickListener {

                                    grantUriPermission(packageName, downloadedUri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
                                    val playIntent = Intent(Intent.ACTION_VIEW)
                                        .setDataAndType(downloadedUri, "video/*")
                                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                                    startActivity(Intent.createChooser(playIntent, "Complete action using"));
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    shortToast(this, "${e.message}")
                }

            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            111 -> {
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {

                    onStartDownloading(tempPost, tempHolder)
                } else {
                    shortToast(this, "Permission denied")
                }
            }
        }
    }

    override fun onPause() {
        currentPlayer?.pause()
        super.onPause()
    }

    override fun onResume() {
        currentPlayer?.play()
        super.onResume()
    }

    override fun onBackPressed() {
        val currentFragment = getCurrentFragment(this)

        if (browser_layout.isVisible) {
            browser_layout.hide()
        } else if (supportFragmentManager.backStackEntryCount == 1
            || currentFragment is FragmentDiscover
            || currentFragment is FragmentCustomFeeds
            || (currentFragment is FragmentHome && currentFragment.calledFor == FOR_MAIN)
            || currentFragment is UserFragment) {
            moveTaskToBack(false)
        } else super.onBackPressed()
    }

    override fun onPlayerAcquired(player: ExoPlayer) {
        currentPlayer = player
    }

    override fun pauseAllPlayers() {
        playerList.forEach {
            it.pause()
        }
    }

    override fun onOpenFragment(fragment: Fragment) {
        openFragment(fragment)
    }

    override fun onLoadMoreData() {
        val fh = getCurrentFragment(this) as FragmentHome
        fh.onLoadMoreData()
    }

    override fun onStartDownloading(
        post: Submission?,
        holder: VideoAdapter.VideoViewHolder?,
        aboutPost: AboutPost?,
        bsdView: View?
    ) {
        val permalink = post?.let { "https://www.reddit.com$it.permalink" } ?: aboutPost!!.permalink
        val name = (post?.title ?: aboutPost!!.title).removeSpecialChars().replace(" ", "_")
        shortToast(this, "Download started")
        holder?.itemView?.progress_download?.show()
        holder?.itemView?.iv_download?.hide()
        var audioUrl = ""

        ioScope().launch {
            if (!hasAudio(permalink, this@MainActivity)) {
                audioUrl = "false"
            }

            mainScope().launch {
                val url = if (post != null) {
                    if (post.postHint == HOSTED_VIDEO) {
                        val fallbackUrl = post.embeddedMedia?.redditVideo?.fallbackUrl ?: "null"
                        audioUrl = audioUrl.ifEmpty {
                            fallbackUrl.substring(0, fallbackUrl.indexOf("DASH_")) + "DASH_audio.mp4?source=fallback"
                        }
                        "https://sd.redditsave.com/download.php?permalink=$permalink&video_url=$fallbackUrl&audio_url=$audioUrl"
                    } else {
                        getGifMp4(post.permalink, client).second
                    }
                } else {
                    if (aboutPost!!.downloadLink.contains("DASH_", false)) {
                        val fallbackUrl = aboutPost.downloadLink
                        audioUrl = audioUrl.ifEmpty {
                            fallbackUrl.substring(0, fallbackUrl.indexOf("DASH_")) + "DASH_audio.mp4?source=fallback"
                        }
                        "https://sd.redditsave.com/download.php?permalink=$permalink&video_url=$fallbackUrl&audio_url=$audioUrl"
                    } else aboutPost.downloadLink
                }

                Log.d(TAG, "onStartDownloading: $url")

                try {
                    val request = DownloadManager.Request(Uri.parse(url))
                    request.setAllowedNetworkTypes(DownloadManager.Request.NETWORK_WIFI or DownloadManager.Request.NETWORK_MOBILE)
                        .setDescription("Downloading reddit video...")
                        .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                        .setDestinationInExternalPublicDir(Environment.DIRECTORY_MOVIES, "Viddit/$name.mp4")

                    val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                    val id = manager.enqueue(request)

                    val receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            val mId = intent?.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1)
                            if (id == mId) {
                                longToast(this@MainActivity, "Downloaded $name.mp4 to Movies/Viddit")
                                holder?.itemView?.apply {
                                    progress_download?.hide()
                                    iv_download.show()
                                }
                                bsdView?.apply {
                                    progress_download_bsd?.hide()
                                    iv_play_bsd.show()
                                    tv_downloading.text = "Downloaded $name.mp4 to Movies/Viddit"
                                }

                                downloadedUri = manager.getUriForDownloadedFile(id)
                            }
                        }
                    }

                    registerReceiver(receiver, IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE))
                } catch (e: Exception) {
                    shortToast(this@MainActivity, "${e.message}")
                    bsdView?.apply {
                        progress_download_bsd.hide()
                        iv_thumb_bsd.setImageResource(android.R.drawable.ic_menu_report_image)
                        tv_downloading.text = "Link is not valid"
                    }
                }
            }
        }
    }

    override fun onLoadMoreDataSR() {
        val srf = getCurrentFragment(this) as SubredditFragment
        srf.onLoadMoreDataSR()
    }

    fun restartFragment(fragmentId: Int) {
        val currentFragment = this.supportFragmentManager.findFragmentById(fragmentId)!!

        this.supportFragmentManager.beginTransaction()
            .detach(currentFragment)
            .commit()
        this.supportFragmentManager.beginTransaction()
            .attach(currentFragment)
            .commit()
    }
}