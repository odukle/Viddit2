package com.odukle.viddit.fragments

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import androidx.lifecycle.ViewModelProvider
import android.os.Bundle
import androidx.fragment.app.Fragment
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.content.ContextCompat.startActivity
import com.bumptech.glide.Glide
import com.google.android.material.snackbar.Snackbar
import com.odukle.viddit.MainActivity
import com.odukle.viddit.R
import com.odukle.viddit.utils.*
import kotlinx.android.synthetic.main.fragment_user.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import net.dean.jraw.RedditClient

class UserFragment : Fragment() {

    companion object {
        fun newInstance() = UserFragment()
    }

    private lateinit var viewModel: UserViewModel
    private lateinit var activity: MainActivity
    private lateinit var userName: String
    private lateinit var reddit: RedditClient

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_user, container, false)
    }

    @SuppressLint("SetTextI18n")
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        activity = requireActivity() as MainActivity
        viewModel = ViewModelProvider(this)[UserViewModel::class.java]

        activity.redditLive.observe(viewLifecycleOwner) { rc ->
            reddit = rc
            if (rc.authManager.currentUsername() == USER_LESS) {
                layout_user.hide()
                btn_sign_in_user.show()
            } else {
                if (isOnline(activity)) {
                    viewModel.getUserIcon(rc.me().username, activity.client)
                    ioScope().launch {
                        val postKarma: Int? = rc.me().query().account?.linkKarma
                        val commentKarma: Int? = rc.me().query().account?.commentKarma
                        if (tv_post_karma == null) return@launch
                        mainScope().launch {
                            tv_post_karma.text = "Post karma: " + postKarma.toString()
                            tv_comment_karma.text = "Comment karma: " + commentKarma.toString()
                        }
                    }
                    mainScope().launch {
                        tv_user_name.text = rc.me().username
                    }
                }
                userName = rc.me().username
                layout_user.show()
                shimmer_icon_user.show()
                btn_sign_in_user.hide()
            }
        }

        viewModel.userIcon.observe(viewLifecycleOwner) {
            if (isOnline(activity)) {
                Glide.with(activity)
                    .load(it)
                    .placeholder(R.drawable.ic_reddit_user)
                    .into(iv_icon_user)
                shimmer_icon_user.hide()
            }
        }

        btn_sign_in_user.setOnClickListener {
            activity.startSignIn()
        }

        btn_sign_out.setOnClickListener {
            if (!isOnline(activity)) {
                showNoInternetToast(activity)
                return@setOnClickListener
            }
            Snackbar.make(requireView(), "u/$userName", Snackbar.LENGTH_SHORT)
                .setAction("Sign out") {
                    ioScope().launch {
                        shortToast(activity, "Signing you out...")
                        reddit.authManager.revokeAccessToken()
                        reddit.authManager.revokeRefreshToken()
                        shortToast(activity, "Signed out")
                        delay(200)
                        activity.triggerRebirth()
                    }
                }.show()
        }
    }

    override fun onResume() {
        activity.window.setLayout(
            ConstraintLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.MATCH_PARENT
        )
        super.onResume()
    }

}