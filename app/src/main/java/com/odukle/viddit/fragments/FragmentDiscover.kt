package com.odukle.viddit.fragments

import androidx.lifecycle.ViewModelProvider
import android.os.Bundle
import androidx.fragment.app.Fragment
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import com.odukle.viddit.MainActivity
import com.odukle.viddit.R

class FragmentDiscover : Fragment() {

    companion object {
        fun newInstance() = FragmentDiscover()
    }

    private lateinit var viewModel: DiscoverViewModel
    private lateinit var activity: MainActivity

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_discover, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        viewModel = ViewModelProvider(this)[DiscoverViewModel::class.java]
        activity = requireActivity() as MainActivity
    }

}