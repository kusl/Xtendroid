package org.xtendroid.xtendroidtest.adapter

import android.view.View
import android.view.ViewGroup
import java.util.List
import org.xtendroid.adapter.AndroidAdapter
import org.xtendroid.adapter.AndroidViewHolder
import org.xtendroid.xtendroidtest.R
import org.xtendroid.xtendroidtest.models.User

/**
 * Example of setting up an adapter with a ViewHolder
 */
@AndroidAdapter class AdapterWithViewHolder {
   List<User> users
   
   // Viewholder
   @AndroidViewHolder(R.layout.list_row_user) static class ViewHolder {
   }
      
   override getView(int position, View convertView, ViewGroup parent) {
      var vh = ViewHolder.getOrCreate(context, convertView, parent)
      
      var item = getItem(position)
      vh.userName.text = item.firstName + " " + item.lastName
      vh.userAge.text = String.valueOf(item.age)
      
      vh.getView()     
   }
   
}

