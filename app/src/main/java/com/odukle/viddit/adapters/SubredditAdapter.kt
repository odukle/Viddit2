package com.odukle.viddit.adapters

import android.graphics.drawable.Drawable
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.annotation.Nullable
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.DataSource
import com.bumptech.glide.load.engine.GlideException
import com.bumptech.glide.request.RequestListener
import com.bumptech.glide.request.target.Target
import com.odukle.viddit.MainActivity
import com.odukle.viddit.R
import com.odukle.viddit.fragments.FragmentHome
import com.odukle.viddit.utils.HOT
import com.odukle.viddit.utils.hide
import com.odukle.viddit.utils.show
import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.Moshi
import com.squareup.moshi.Types
import kotlinx.android.synthetic.main.item_view_subreddit.view.*
import net.dean.jraw.JrawUtils
import net.dean.jraw.models.Submission
import java.lang.reflect.Type

class SubredditAdapter(var vList: MutableList<Submission>, val sorting: String = HOT) : RecyclerView.Adapter<SubredditAdapter.SRViewHolder>() {

    lateinit var activity: MainActivity

    inner class SRViewHolder(view: View) : RecyclerView.ViewHolder(view) {

        fun populateViewHolder(post: Submission, position: Int) {
            itemView.apply {
                Glide.with(this)
                    .load(post.thumbnail)
                    .centerCrop()
                    .addListener(imageLoadingListener(this))
                    .into(iv_thumb)

                iv_thumb.setOnClickListener {
                    val type: Type = Types.newParameterizedType(
                        MutableList::class.java,
                        Submission::class.java
                    )

                    val jsonAdapter = JrawUtils.moshi.adapter<MutableList<Submission>>(type).serializeNulls()
                    val jsonList = jsonAdapter.toJson(vList)
                    activity.onOpenFragment(FragmentHome.newInstance(false, jsonList, position, post.subreddit, sorting))
                }
            }
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): SRViewHolder {
        activity = parent.context as MainActivity
        val view = LayoutInflater.from(activity).inflate(R.layout.item_view_subreddit, parent, false)
        return SRViewHolder(view)
    }

    override fun onBindViewHolder(holder: SRViewHolder, position: Int) {
        val post = vList[position]
        holder.populateViewHolder(post, position)
    }

    override fun onViewAttachedToWindow(holder: SRViewHolder) {
        val range = (itemCount - 5)..itemCount
        if (holder.bindingAdapterPosition in range) {
            activity.onLoadMoreDataSR()
        }
        super.onViewAttachedToWindow(holder)
    }

    override fun getItemCount(): Int {
        return vList.size
    }

    private fun imageLoadingListener(itemView: View): RequestListener<Drawable?> {
        itemView.progress_thumb.show()
        itemView.iv_play.hide()
        return object : RequestListener<Drawable?> {
            override fun onLoadFailed(@Nullable e: GlideException?, model: Any?, target: Target<Drawable?>?, isFirstResource: Boolean): Boolean {
                itemView.progress_thumb.hide()
                itemView.iv_play.show()
                itemView.iv_thumb.setImageResource(android.R.drawable.ic_menu_report_image)
                return true
            }

            override fun onResourceReady(
                resource: Drawable?,
                model: Any?,
                target: Target<Drawable?>?,
                dataSource: DataSource?,
                isFirstResource: Boolean
            ): Boolean {
                itemView.progress_thumb.hide()
                itemView.iv_play.show()
                return false
            }
        }
    }

    interface OnOpenFragment {
        fun onOpenFragment(fragment: Fragment)
    }

    interface OnLoadMoreDataSR {
        fun onLoadMoreDataSR()
    }
}