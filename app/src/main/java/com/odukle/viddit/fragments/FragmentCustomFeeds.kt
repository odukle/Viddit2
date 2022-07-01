package com.odukle.viddit.fragments

import androidx.lifecycle.ViewModelProvider
import android.os.Bundle
import androidx.fragment.app.Fragment
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import com.odukle.viddit.R

class FragmentCustomFeeds : Fragment() {

    companion object {
        fun newInstance() = FragmentCustomFeeds()
    }

    private lateinit var viewModel: CustomFeedsViewModel

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_custom_feeds, container, false)
    }

    override fun onActivityCreated(savedInstanceState: Bundle?) {
        super.onActivityCreated(savedInstanceState)
        viewModel = ViewModelProvider(this).get(CustomFeedsViewModel::class.java)
        // TODO: Use the ViewModel
    }

}