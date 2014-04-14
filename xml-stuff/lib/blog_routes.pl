#!/usr/bin/perl

use Dancer ':syntax';
use Dancer::Plugin::Database;
use CGI;
use Crypt::SaltedHash;
use Data::UUID;
use DBI;
use POSIX qw(strftime);
use MIME::Lite;
use strict;
use warnings;

#Just in case
our ($error_msg);

# until `prefix undef;` all routes are prefixed with /admin/blog
prefix '/admin/blog';

get '/' => sub {
  my $uuid = session('uuid');
  my $username = session('user');
  my $role = session('role');
  template 'blog_dashboard', {
    username => $username,
    uuid => $uuid,
    page_title => 'Blog Dash'
  };
};

get '/posts/overview' => sub {
  my ($username, $role, $uuid, $sql, $sth, @row);
  $username = session('user');
  $role = session('role');
  $uuid = session('uuid');
  $sql = "SELECT post_id, post_title, post_public, users.user_uuid AS uuid, FROM_UNIXTIME(post_create_date, '%d %b %Y') AS post_create_date, FROM_UNIXTIME(post_change_date, '%d %b %Y') AS post_change_date, users.user_name AS username FROM posts JOIN users ON users.user_uuid = posts.user_uuid ORDER BY post_id DESC;";
  $sth = database->prepare($sql);
  $sth->execute or die $sth->errstr;
  @row = $sth->fetchall_arrayref({}); 
  template 'blog_posts_overview', {
    username => $username,
    role => $role,
    uuid => $uuid,
    row => \@row,
    page_title => "Posts Dash"
  };
};

post '/post/publish' => sub {
  my ($username, $role, $post_id, $public, $timestamp);
  $role = session('role');
  $post_id = params->{'post_id'};
  if ( params->{'public'} ) {
    $public = 1;
  } else {
    $public = 0;
  } 
  #setting timestamp -> current time
  $timestamp = strftime "%s", localtime;
  #check if user is authorized to publish
  if ( $role eq 'author' or $role eq 'admin' ) {
    # updates user-fields
    database->quick_update('posts', { post_id => $post_id }, { post_public => $public, post_change_date => $timestamp });
    # directly redirect to same page without notice
    redirect '/admin/blog/posts/overview';
  } else {
    my $error_msg = "You cannot publish posts or make them private.";
    template 'message', { error => $error_msg, msg_link => '/admin/blog/posts/overview', msg_link_text => 'Return to overview' };
  }
};


get '/post/new' => sub {
  my ($username, $role, $uuid);
  template 'blog_new_post', {
    page_title => 'New Post' 
  };
};

post '/post/new' => sub {
  my ($role, $uuid, $title, $text, $slug, $tags, @tags, $public, $lang, $timestamp, $sql, $sth, @post_res, $post_id, $post_slug_count, $tags_tag_is, $tags_tag_id, $tags_posts_con_count);
  $role = session('role');
  $uuid = params->{'uuid'};
  $lang = params->{'language'};

  if ( ! params->{'title'} or ! params->{'text'} ) {
    $error_msg = "Please fill out all required fields.";
    return 'blog_new_post', { role => $role, error => $error_msg };
  } else {
    $title = params->{'title'};
    $text = params->{'text'};
    $slug = $title;
    #title gets converted to slug
    $slug =~ s/  / /g;
    #spaces get converted to dashes
    $slug =~ s/ /-/g;
    #so called "Umlaute" are converted to their equivalents
    $slug =~ s/ä/ae/g;
    $slug =~ s/ö/oe/g;
    $slug =~ s/ü/ue/g;
    $slug =~ s/ß/ss/g;

    # check if there is another post with the same slug
    $post_slug_count = database->quick_count('posts', { post_slug => $slug });
    if ( params->{'tags'} ) {
      $tags = params->{'tags'};
    } else {
      $tags = '';
    }

    if ( $post_slug_count gt 0 ) {
      return template 'blog_new_post', {
        uuid => $uuid,
        title => $title,
        text => $text,
        tags => $tags,
        lang => $lang,
        tags => $tags,
        error => "This title is already used, please modify it."
      }; 
    }
  }

  #handle public state which determines whether or not a post is public or not
  if ( params->{'public'} ) {
    $public = 1;
  } else {
    $public = 0;
  }
  

  #setting timestamp -> current time
  $timestamp = strftime "%s", localtime;
  #inserting values into database
  database->quick_insert('posts', {
      post_title => $title,
      post_text => $text,
      post_slug => $slug,
      post_create_date => $timestamp,
      user_uuid => $uuid,
      post_public => $public,
      post_lang => $lang
    });

  $sth = $sql = undef;
  #selecting the id of the new post
  $post_id = database->quick_lookup('posts', { post_slug => $slug }, 'post_id');
# $post_id = $post_res[0];

  #inserting or updating tags
  if ( params->{'tags'} ) {
    $tags = params->{'tags'};
    # get rid of spaces in $tags
    $tags =~ s/ //g;
    # split $tags and push each item into an array (@tags)
    @tags = split /,/, $tags;
    foreach (@tags) {
      $tags_tag_is = database->quick_select('tags', { tag_slug => $_ });
      # check whether or not a tag is already in tags
      if ( $tags_tag_is and $tags_tag_is ne 0 ) {
        # tag is already in table(tags)
        # lookup the id of $_
        $tags_tag_id = database->quick_lookup('tags', { tag_slug => $_ }, 'tag_id');
        # check if connection post_id - tag_id is already made
        $tags_posts_con_count = database->quick_count('tags_posts', { tag_id => $tags_tag_id, post_id => $post_id });
        if ( $tags_posts_con_count eq 0 ) {
          # connection hasn't been made yet
          # insert connection post_id - tag_id into table(tags_posts)
          database->quick_insert('tags_posts', { post_id => $post_id, tag_id => $tags_tag_id });
        }
      } elsif ( ! $tags_tag_is ) {
        # tag is not yet in table(tags)
        # insert $_ into table(tags)
        database->quick_insert('tags', { tag_slug => $_ });
        # lookup the id of $_
        $tags_tag_id = database->quick_lookup('tags', { tag_slug => $_ }, 'tag_id');
        # insert connection post_id - tag_id into table(tags_posts)
        database->quick_insert('tags_posts', { post_id => $post_id, tag_id => $tags_tag_id });
      }
    }
  }
  redirect '/admin/blog/posts/overview';
};

get '/post/edit/:post_id' => sub {
  my ($role, $uuid, $username, $post_id, $sql, $sth, @row, @tags, $tags, $tag);
  $username = session('user');
  $post_id = params->{'post_id'};
  $sth = database->prepare("SELECT post_title, post_text, post_public, post_lang FROM posts WHERE post_id=?;");
  $sth->execute($post_id) or die $sth->errstr; 
  @row = $sth->fetchrow_array;
  $tags = '';
  $sql = "SELECT tag_slug FROM tags JOIN tags_posts ON post_id = ? AND tags_posts.tag_id = tags.tag_id;";
  $sth = database->prepare($sql);
  $sth->execute($post_id) or die $sth->errstr;
  while (@tags = $sth->fetchrow_array) {
    $tags .= "$tags[0], ";
  }
#  my @tags = database->quick_select('tags_posts', { post_id => $post_id });
#  foreach (@tags) {
    #loop through the array of hashes (@tags) and concatenate each value of 'tag_id' with $tags
#    $tags .= "$_->{tag_id},";
#  }
  # get rid of the last comma (,)
  $tags =~ s/, $//;
  template 'blog_edit_post', {
    uuid => $uuid,
    post_id => $post_id,
    title => $row[0],
    text => $row[1],
    public => $row[2],
    lang => $row[3],
    tags => $tags,
    page_title => 'Edit Post'
  };
};

post '/post/edit' => sub {
  
  my ($role, $uuid, $title, $text, $slug, $tags, @tags, $public, $lang, $timestamp, @post_res, $post_id, $post_slug_count, $tags_tag_is, $tags_tag_id, $tags_posts_con_count);
  $role = session('role');
  $uuid = params->{'uuid'};
  $lang = params->{'language'};
  $post_id = params->{'post_id'};

  if ( ! params->{'title'} or ! params->{'text'} ) {
    $error_msg = "Please fill out all required fields.";
    return 'blog_new_post', { role => $role, error => $error_msg };
  } else {
    $title = params->{'title'};
    $text = params->{'text'};
    $slug = $title;
    #title gets converted to slug
    $slug =~ s/  / /g;
    #spaces get converted to dashes
    $slug =~ s/ /-/g;
    #so called "Umlaute" are converted to their equivalents
    $slug =~ s/ä/ae/g;
    $slug =~ s/ö/oe/g;
    $slug =~ s/ü/ue/g;
    $slug =~ s/ß/ss/g;
    # count the number of posts in which post_slug equals $slug
    $post_slug_count = database->quick_count('posts', { post_slug => $slug });
    # check if there is another post with the same slug
    # because this one is still in the db the amount has to be greater than 1 not 0
    if ( $post_slug_count gt 1 ) {
      return template 'blog_new_post', {
        uuid => $uuid,
        title => $title,
        text => $text,
        tags => $tags,
        error => "This title is already used, please modify it."
      }; 
    }
  }

  #handle public state which determines whether or not a post is public or not
  if ( params->{'public'} ) {
    $public = 1;
  } else {
    $public = 0;
  }
  

  #setting timestamp -> current time
  $timestamp = strftime "%s", localtime;
#  return $timestamp;
  #inserting values into database
  database->quick_update('posts', { post_id => $post_id }, {
      post_title => $title,
      post_text => $text,
      post_slug => $slug,
      post_change_date => $timestamp,
      user_uuid => $uuid,
      post_public => $public,
      post_lang => $lang
    });

  #inserting or updating tags
  $tags = params->{'tags'};
  # delete all connections between this post and a tag
  # so it is easier to handle tags wich do not longer relate to this post
  database->quick_delete('tags_posts', { post_id => $post_id });
  # get rid of spaces in $tags
  $tags =~ s/ //g;
  # split $tags and push each item into an array (@tags)
  @tags = split /,/, $tags;
  foreach (@tags) {
    $tags_tag_is = database->quick_select('tags', { tag_slug => $_ });
    # check whether or not a tag is already in tags
    if ( $tags_tag_is and $tags_tag_is ne 0 ) {
      # tag is already in table(tags)
      # lookup the id of $_
      $tags_tag_id = database->quick_lookup('tags', { tag_slug => $_ }, 'tag_id');
      # check if connection post_id - tag_id is already made
      $tags_posts_con_count = database->quick_count('tags_posts', { tag_id => $tags_tag_id, post_id => $post_id });
      if ( $tags_posts_con_count eq 0 ) {
        # connection hasn't been made yet
        # insert connection post_id - tag_id into table(tags_posts)
        database->quick_insert('tags_posts', { post_id => $post_id, tag_id => $tags_tag_id });
      }
    } elsif ( ! $tags_tag_is ) {
      # tag is not yet in table(tags)
      # insert $_ into table(tags)
      database->quick_insert('tags', { tag_slug => $_ });
      # lookup the id of $_
      $tags_tag_id = database->quick_lookup('tags', { tag_slug => $_ }, 'tag_id');
      # insert connection post_id - tag_id into table(tags_posts)
      database->quick_insert('tags_posts', { post_id => $post_id, tag_id => $tags_tag_id });
    }
  }
#  template 'blog_edit_post', { role => $role, post_id => $post_id };
  redirect "/admin/blog/post/edit/$post_id";
};

get '/post/delete/:post_id' => sub {
  if ( session('role') ne 'editor' ) {
    if ( params->{'post_id'} ) {
      database->quick_delete('posts', { post_id => params->{'post_id'} });
    }
  }
  redirect '/admin/blog/posts/overview';
};


get '/tags/overview' => sub {
  my ($role, $sql, $sth, @row);
  $role = session('role');
  $sql = "SELECT tags.tag_slug, tags.tag_id, count(*) AS amount FROM tags JOIN tags_posts AS con ON con.tag_id = tags.tag_id GROUP BY tag_id ORDER BY amount DESC;";
  $sth = database->prepare($sql);
  $sth->execute or die $sth->errstr;
  @row = $sth->fetchall_arrayref({}); 
  return template 'blog_tags_overview', {
    role => $role,
    row => \@row,
    page_title => 'Tags Dash'
  };
};

# deletes a specific tag with tag_id
post '/tag/delete' => sub {
  if ( session('user') ne 'editor' ) {
    my $tag_id = params->{'tag_id'};
    database->quick_delete('tags', { tag_id => $tag_id });
  }
  redirect '/admin/blog/tags/overview';
};

# deletes all connections between posts and this tag_id
post '/tag/reset' => sub {
  if ( session('user') ne 'editor' ) {
    my $tag_id = params->{'tag_id'};
    database->quick_delete('tags_posts', { tag_id => $tag_id });
  }
  redirect '/admin/blog/tags/overview';
};

# unset the prefix /admin/blog
prefix undef;
