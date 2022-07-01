package com.odukle.viddit.adapters

import android.annotation.SuppressLint
import android.net.Uri
import android.util.Log
import android.view.*
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.Observer
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.google.android.exoplayer2.ExoPlayer
import com.google.android.exoplayer2.MediaItem
import com.google.android.exoplayer2.util.MimeTypes
import com.google.android.gms.ads.*
import com.google.android.gms.ads.nativead.NativeAd
import com.odukle.viddit.MainActivity
import com.odukle.viddit.R
import com.odukle.viddit.fragments.SubredditFragment
import com.odukle.viddit.models.SubReddit
import com.odukle.viddit.utils.*
import kotlinx.android.synthetic.main.item_view_ad.view.*
import kotlinx.android.synthetic.main.item_view_video.view.*
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
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
            activity.onLoadMoreData()
        }
    }

    override fun onViewAttachedToWindow(holder: RecyclerView.ViewHolder) {
        if (getItemViewType(holder.bindingAdapterPosition) == ITEM_VIDEO) {
            holder as VideoAdapter.VideoViewHolder
            val post = vList[holder.bindingAdapterPosition] as Submission
            if (holder.playerReleased) setupPlayer(holder, post)
            if (firstRun) {
                try {
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
                    else holder.player.play()
                    activity.onPlayerAcquired(holder.player)
                }
            }
        }


        super.onViewAttachedToWindow(holder)
    }

    override fun onViewDetachedFromWindow(holder: RecyclerView.ViewHolder) {
        if (getItemViewType(holder.bindingAdapterPosition) == ITEM_VIDEO) {
            holder as VideoViewHolder
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
        return if (position != 0 && position % 5 == 0) ITEM_AD else ITEM_VIDEO
    }


    private fun setupPlayer(holder: VideoViewHolder, post: Submission) {
        val playerView = holder.itemView.player_view

        val player = activity.acquire()
        holder.player = player
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
            Log.d(TAG, "setupPlayer: ${holder.bindingAdapterPosition} is a gif")
            holder.itemView.gif_loader.show()
            holder.gifJob?.cancel()
            holder.gifJob = ioScope().launch {
                holder.gifMp4 = getGifMp4(post.permalink, activity.client).second
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
            if (it == View.VISIBLE) {
                holder.itemView.layout_stats.hide()
                holder.itemView.layout_subreddit_n_desc.hide()
                holder.itemView.layout_user.hide()
            } else {
                holder.itemView.layout_stats.show()
                holder.itemView.layout_subreddit_n_desc.show()
                holder.itemView.layout_user.show()
            }
        }
    }

    private fun setVote(post: Submission, holder: VideoAdapter.VideoViewHolder) {
        holder.itemView.apply {
            try {
                if (post.vote == VoteDirection.UP) {
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
                tv_comments.text = post.commentCount.toString()
                tv_upvotes.text = bindingAdapterPosition.toString()
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
                        activity.openFragment(SubredditFragment.newInstance(post.subreddit))
                    }
                }
            }
        }
    }

    inner class AdViewHolder(view: View) : RecyclerView.ViewHolder(view)

    interface OnAdapterCallback {
        fun onLoadMoreData()
    }

    interface OnPlayerAcquired {
        fun onPlayerAcquired(player: ExoPlayer)
    }
}