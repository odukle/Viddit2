package com.odukle.viddit.adapters

import android.annotation.SuppressLint
import android.content.pm.PackageManager
import android.net.Uri
import android.util.Log
import android.view.*
import androidx.appcompat.widget.ThemedSpinnerAdapter
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.Observer
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.google.android.exoplayer2.ExoPlayer
import com.google.android.exoplayer2.MediaItem
import com.google.android.exoplayer2.Player
import com.google.android.exoplayer2.util.MimeTypes
import com.google.android.gms.ads.*
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.material.snackbar.Snackbar
import com.odukle.viddit.MainActivity
import com.odukle.viddit.R
import com.odukle.viddit.fragments.FragmentHome
import com.odukle.viddit.fragments.SubredditFragment
import com.odukle.viddit.models.AboutPost
import com.odukle.viddit.models.SubReddit
import com.odukle.viddit.utils.*
import kotlinx.android.synthetic.main.item_view_ad.view.*
import kotlinx.android.synthetic.main.item_view_video.view.*
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import net.dean.jraw.RedditClient
import net.dean.jraw.models.Submission
import net.dean.jraw.models.VoteDirection

private const val TAG = "VideoAdapter"
private const val ITEM_VIDEO = 101
private const val ITEM_AD = 102
private const val AD_UNIT_ID = "ca-app-pub-9193191601772541/3875789301"

class VideoAdapter(var vList: MutableList<Any>) :
    RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    private lateinit var playOnDetach: Runnable
    private var firstRun = true
    private lateinit var activity: MainActivity
    private lateinit var adLoader: AdLoader
    private var nativeAd: MutableLiveData<NativeAd?> = MutableLiveData(null)
    private var loadAds: Runnable
    var content: String = FRONT_PAGE

    init {
        loadAds = Runnable { setUpAds() }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        if (!this::activity.isInitialized) {
            activity = parent.context as MainActivity
            loadAds.run()
        }
        return if (viewType == ITEM_VIDEO) {
            val videoView = LayoutInflater.from(activity).inflate(R.layout.item_view_video, parent, false)
            videoView.layout_subreddit_n_desc.layoutTransition.setAnimateParentHierarchy(false)
            VideoViewHolder(videoView)
        } else {
            val adView = LayoutInflater.from(parent.context).inflate(R.layout.item_view_ad, parent, false)
            AdViewHolder(adView)
        }
    }

    @SuppressLint("SetTextI18n")
    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        if (getItemViewType(position) == ITEM_VIDEO) {
            holder as VideoViewHolder
            val post = vList[position] as Submission
            holder.populateViewHolder(post)
        } else {
            holder as AdViewHolder
            nativeAd.observe(activity, getAdObserver(holder))
        }

        val range = (itemCount - 5)..itemCount
        if (position in range) {
            (getCurrentFragment(activity) as FragmentHome).onLoadMoreData()
        }
    }

    override fun onViewAttachedToWindow(holder: RecyclerView.ViewHolder) {
        if (getItemViewType(holder.bindingAdapterPosition) == ITEM_VIDEO) {
            holder as VideoAdapter.VideoViewHolder
            (getCurrentFragment(activity) as FragmentHome).onShowChips()
            val post = vList[holder.bindingAdapterPosition] as Submission
            if (holder.playerReleased) setupPlayer(holder, post)
            if (!post.isNsfw || (post.isNsfw && nsfwAllowed(activity))) {
                if (firstRun) {
                    try {
                        activity.pauseAllPlayers()
                        holder.player.play()
                    } catch (e: Exception) {
                        runAfter(100) {
                            holder.player.play()
                        }
                    }
                    firstRun = false
                }

                playOnDetach = Runnable {
                    if (!holder.playerReleased) {
                        if (holder.player.isLoading) holder.player.playWhenReady = true
                        else {
                            activity.pauseAllPlayers()
                            holder.player.play()
                        }
                        activity.onPlayerAcquired(holder.player)
                    }
                }
            } else {
                if (holder.isPlayerInitialized()) holder.player.pause()
                holder.itemView.layout_nsfw.show()
            }
        } else {
            (getCurrentFragment(activity) as FragmentHome).onHideChips()
        }


        super.onViewAttachedToWindow(holder)
    }

    override fun onViewDetachedFromWindow(holder: RecyclerView.ViewHolder) {
        if (getItemViewType(holder.bindingAdapterPosition) == ITEM_VIDEO) {
            if (holder is VideoViewHolder) {
                val releasePlayer = Runnable {
                    holder.player.pause()
                    activity.release(holder.player)
                    holder.playerReleased = true
                }

                if (holder.isPlayerInitialized()) releasePlayer.run()
                else runAfter(100) {
                    if (holder.isPlayerInitialized()) releasePlayer.run()
                }
            }
        }
        try {
            playOnDetach.run()
        } catch (e: Exception) {
        }

        super.onViewDetachedFromWindow(holder)
    }

    override fun getItemCount(): Int {
        return vList.size
    }

    override fun getItemViewType(position: Int): Int {
        return if (position != 0 && position % AD_DIST == 0) ITEM_AD else ITEM_VIDEO
    }


    private fun setupPlayer(holder: VideoViewHolder, post: Submission) {
        val playerView = holder.itemView.player_view

        val player = activity.acquire()
        holder.player = player
        holder.addPlayBackListener(holder.player)
        holder.setMute(holder.player)
        holder.playerReleased = false
        player.repeatMode = ExoPlayer.REPEAT_MODE_ONE
        playerView.controllerAutoShow = false
        playerView.player = null
        playerView.player = player
        val video = post.embeddedMedia?.redditVideo?.hlsUrl
        if (video != null) {
            val mimeType = MimeTypes.APPLICATION_M3U8
            val mediaItem = MediaItem.Builder()
                .setUri(Uri.parse(video))
                .setMimeType(mimeType)
                .build()
            player.setMediaItem(mediaItem)
            player.prepare()
        } else {
            holder.itemView.gif_loader.show()
            holder.gifJob?.cancel()
            holder.gifJob = ioScope().launch {
                holder.gifMp4 = getGifMp4(post.permalink, activity.client).second
                Log.d(TAG, "setupPlayer: ${holder.gifMp4}")
                Log.d(TAG, "setupPlayer: ${post.postHint}")
                if (holder.playerReleased) return@launch
                mainScope().launch {
                    val mimeType = MimeTypes.APPLICATION_MP4
                    val mediaItem = MediaItem.Builder()
                        .setUri(Uri.parse(holder.gifMp4))
                        .setMimeType(mimeType)
                        .build()
                    player.setMediaItem(mediaItem)
                    player.prepare()
                    player.playWhenReady = true
                    holder.itemView.gif_loader.hide()
                    holder.gifJob = null
                }
            }
        }

        playerView.setControllerVisibilityListener {
            holder.itemView.apply {
                if (it == View.VISIBLE) {
                    layout_stats.hide()
                    layout_subreddit_n_desc.hide()
                    layout_user.hide()
                    btn_toggle_play.show()
                    if (post.isNsfw && nsfwAllowed(activity)) uncheck_nsfw.show()
                    btn_mute.show()
                } else {
                    layout_stats.show()
                    layout_subreddit_n_desc.show()
                    layout_user.show()
                    btn_toggle_play.hide()
                    uncheck_nsfw.hide()
                    btn_mute.hide()
                }
            }
        }
    }

    private fun setVote(post: Submission, holder: VideoAdapter.VideoViewHolder) {
        ioScope().launch {
            holder.itemView.apply {
                try {
                    val submission = activity.reddit.submission(post.id).inspect()
                    if (submission.vote == VoteDirection.UP) {
                        activity.runOnUiThread {
                            iv_upvotes.setImageResource(R.drawable.ic_upvote_red)
                            tv_upvotes.setTextColor(activity.getColor(R.color.orange))
                        }
                    } else {
                        activity.runOnUiThread {
                            iv_upvotes.setImageResource(R.drawable.ic_upvote)
                            tv_upvotes.setTextColor(activity.getColor(R.color.white))
                        }
                    }
                } catch (e: IllegalStateException) {
                }
            }
        }
    }

    private suspend fun setIconImg(post: Submission, holder: VideoAdapter.VideoViewHolder) {
        holder.itemView.apply {
            val (subreddit, userSubreddit) = if (isOnline(activity)) {
                Pair(getSubredditInfo("r/${post.subreddit}", activity.client), getSubredditInfo("u/${post.author}", activity.client))
            } else {
                longToast(activity, "No internet 😔")
                Pair(
                    SubReddit.getEmpty(),
                    SubReddit.getEmpty()
                )
            }

            mainScope().launch {
                Glide.with(this@apply)
                    .load(userSubreddit.icon)
                    .placeholder(R.drawable.ic_reddit_user)
                    .into(iv_user_icon)

                Glide.with(this@apply)
                    .load(subreddit.icon)
                    .placeholder(R.drawable.ic_reddit)
                    .into(iv_icon_sr)

                shimmer_icon.hide()
                shimmer_user_icon.hide()
                iv_icon_sr.show()
                iv_user_icon.show()
            }
        }
    }

    private fun setUpAds() {

        adLoader = AdLoader.Builder(activity, AD_UNIT_ID)
            .forNativeAd { ad ->
                nativeAd.value?.destroy()
                nativeAd.postValue(null)
                nativeAd.postValue(ad)
                if (!adLoader.isLoading) {

                    if (activity.isDestroyed) {
                        ad.destroy()
                        return@forNativeAd
                    }
                }

            }.withAdListener(object : AdListener() {
                override fun onAdFailedToLoad(p0: LoadAdError) {
                    Log.d(TAG, "onAdFailedToLoad: failed -> ${p0.message}")
                    super.onAdFailedToLoad(p0)
                }
            }).build()

        adLoader.loadAd(AdRequest.Builder().build())
    }

    private fun getAdObserver(holder: AdViewHolder) = object : Observer<NativeAd?> {
        override fun onChanged(t: NativeAd?) {
            holder.itemView.my_template.setNativeAd(nativeAd.value)
            removeObserver()
            holder.itemView.progress_bar_ad.hide()
            adLoader.loadAd(AdRequest.Builder().build())
        }

        fun removeObserver() {
            nativeAd.removeObserver(this)
        }
    }

    inner class VideoViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        lateinit var player: ExoPlayer
        var gifMp4: String? = null
        var playerReleased = false
        var gifJob: Job? = null

        fun isPlayerInitialized() = this::player.isInitialized

        @SuppressLint("SetTextI18n")
        fun populateViewHolder(post: Submission) {
            itemView.apply {
                gif_loader.hide()
                tv_comments.text = truncateNumber(post.commentCount.toFloat())
                tv_upvotes.text = truncateNumber(post.score.toFloat())
                tv_user.text = "u/" + post.author + " • " + post.created.time.toTimeAgo()
                tv_title.text = post.title
                tv_full_title.text = post.title
                tv_subreddit.text = "r/" + post.subreddit

                shimmer_icon.show()
                shimmer_user_icon.show()
                iv_icon_sr.hide()
                iv_user_icon.hide()
                mainScope().launch {
                    setupPlayer(this@VideoViewHolder, post)
                    setIconImg(post, this@VideoViewHolder)
                    setVote(post, this@VideoViewHolder)
                }

                arrayOf(tv_subreddit, iv_icon_sr).forEach { view ->
                    view.setOnClickListener {
                        activity.onOpenFragment(SubredditFragment.newInstance(post.subreddit))
                    }
                }

                arrayOf(tv_user, iv_user_icon).forEach {
                    it.setOnClickListener {
                        activity.onOpenFragment(SubredditFragment.newInstance(post.author, true))
                    }
                }

                tv_title.setOnClickListener {
                    tv_title.hide()
                    tv_full_title.show()
                }

                tv_full_title.setOnClickListener {
                    tv_full_title.hide()
                    tv_title.show()
                }

                btn_watch_anyway.setOnClickListener {
                    layout_nsfw.hide()
                    player.play()
                    if (check_nsfw.isChecked) {
                        allowNSFW(activity)
                    }
                }

                uncheck_nsfw.setOnCheckedChangeListener { _, isChecked ->
                    if (isChecked) {
                        doNotAllowNSFW(activity)
                        check_nsfw.isChecked = false
                        layout_nsfw.show()
                        player.pause()
                    } else allowNSFW(activity)
                }

                arrayOf(iv_upvotes, tv_upvotes).forEach {
                    it.setOnClickListener {
                        vote(VoteDirection.UP, activity.reddit, post.id, post.score, this@VideoViewHolder)
                    }
                }

                iv_downvote.setOnClickListener {
                    vote(VoteDirection.DOWN, activity.reddit, post.id, post.score, this@VideoViewHolder)
                }

                btn_toggle_play.setOnClickListener {
                    if (player.isPlaying) {
                        player.pause()
                    } else {
                        player.play()
                    }
                }

                btn_mute.setOnClickListener {
                    if (player.volume > 0f) {
                        player.volume = 0f
                        btn_mute.setImageResource(R.drawable.ic_mute)
                        activity.playOnMute = true
                    } else {
                        player.volume = 1f
                        btn_mute.setImageResource(R.drawable.ic_volume)
                        activity.playOnMute = false
                    }
                }

                iv_download.setOnClickListener {
                    iv_download.bounce()
                    if (activity.checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_DENIED) {
                        activity.tempPost = post
                        activity.tempHolder = this@VideoViewHolder
                        activity.requestPermissions(
                            arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE),
                            111
                        )
                    } else {
                        activity.onStartDownloading(post, this@VideoViewHolder)
                    }
                }

                iv_comments.setOnClickListener {
                    (getCurrentFragment(activity) as FragmentHome).showComments(post.permalink)
                }
            }
        }

        fun addPlayBackListener(player: ExoPlayer) {
            player.addListener(object : Player.Listener {
                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    if (isPlaying) {
                        itemView.btn_toggle_play.setImageResource(R.drawable.ic_pause)
                    } else {
                        itemView.btn_toggle_play.setImageResource(R.drawable.ic_round_play_circle_filled_24)
                    }
                    super.onIsPlayingChanged(isPlaying)
                }
            })
        }

        fun setMute(player: ExoPlayer) {
            if (activity.playOnMute) {
                player.volume = 0f
                itemView.btn_mute.setImageResource(R.drawable.ic_mute)
            } else {
                player.volume = 1f
                itemView.btn_mute.setImageResource(R.drawable.ic_volume)
            }
        }
    }


    private fun vote(
        dir: VoteDirection,
        reddit: RedditClient?,
        id: String,
        score: Int,
        holder: VideoAdapter.VideoViewHolder
    ) {
        if (activity.reddit.authManager.currentUsername() == USER_LESS) {
            activity.onShowSignInDialog()
            return
        }

        holder.itemView.apply {
            val strVote = if (dir == VoteDirection.UP) "upvote" else "downvote"
            val strVoted = if (dir == VoteDirection.UP) "Upvoted" else "Downvoted"
            val tv = if (dir == VoteDirection.UP) tv_upvotes else null
            val iv = if (dir == VoteDirection.UP) iv_upvotes else iv_downvote
            val tvEx = if (dir == VoteDirection.UP) null else tv_upvotes
            val ivEx = if (dir == VoteDirection.UP) iv_downvote else iv_upvotes
            val src = if (dir == VoteDirection.UP) R.drawable.ic_upvote else R.drawable.ic_downvote
            val srcEx = if (dir == VoteDirection.UP) R.drawable.ic_downvote else R.drawable.ic_upvote
            val srcRed = if (dir == VoteDirection.UP) R.drawable.ic_upvote_red else R.drawable.ic_downvote_red
            if (reddit == null) {
                holder.player.pause()
                Snackbar.make(rootView, "Sign in to $strVote", Snackbar.LENGTH_SHORT)
                    .setAction("Sign in") { activity.startSignIn() }.show()
            } else {
                ioScope().launch {
                    shortToast(activity, "Voting...")
                    val submission = reddit.submission(id)
                    val voteDir = submission.inspect().vote
                    if (voteDir != dir) {
                        //change vote image color
                        mainScope().launch {
                            shortToast(activity, strVoted)
                            iv.setImageResource(srcRed)
                            tv?.setTextColor(activity.getColor(R.color.orange))
                            iv.bounce(); tv?.bounce()
                            if (voteDir != VoteDirection.NONE) {
                                ivEx.setImageResource(srcEx)
                                tvEx?.setTextColor(activity.getColor(R.color.white))
                            }
                            tv_upvotes.text = if (dir == VoteDirection.DOWN) (score - 1).toString() else (score + 1).toString()
                        }
                        //upvote
                        submission.setVote(dir)
                    } else {
                        //change vote image color
                        mainScope().launch {
                            shortToast(activity, "Removed $strVote")
                            iv.setImageResource(src)
                            iv.bounce(); tv?.bounce()
                            tv?.setTextColor(activity.getColor(R.color.white))
                            tv_upvotes.text = if (dir == VoteDirection.DOWN) (score + 1).toString() else (score - 1).toString()
                        }
                        //remove vote
                        submission.setVote(VoteDirection.NONE)
                    }
                }
            }
        }
    }

    inner class AdViewHolder(view: View) : RecyclerView.ViewHolder(view)

    interface OnActivityCallback {
        fun onStartDownloading(
            post: Submission?,
            holder: VideoAdapter.VideoViewHolder?,
            aboutPost: AboutPost? = null,
            bsdView: View? = null
        )
        fun onShowSignInDialog()
    }

    interface OnFragmentCallback {
        fun onLoadMoreData()
        fun onHideChips()
        fun onShowChips()
        fun showComments(permalink: String)
    }

    interface OnPlayerAcquired {
        fun onPlayerAcquired(player: ExoPlayer)
    }
}