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

# set prefix /admin
prefix '/admin';

get '/' => sub {
  my $username = session('user');
  my $role = session('role');
  template 'admin', {
    username => $username,
    role => $role,
    page_title => 'Dashboard'
  };
};

get '/users' => sub {
  my ($username, $role, $sql, $sth, @row);
  $username = session('user');
  $role = session('role');
  if ( $role eq 'admin' ) {
    # select all users except the one logged in
    $sql = "SELECT user_uuid, user_name, user_status, user_create_date, user_role FROM `users` WHERE user_name NOT LIKE ?;";
    $sth = database->prepare($sql);
    $sth->execute($username);
    @row = $sth->fetchall_arrayref({}); 
    template 'admin_users', {
      row => \@row,
      page_title => 'Edit Users'
    };
  } else {
    redirect '/admin';
  }
};

# handles user-changes
post '/users' => sub {
  my $status;
  if ( params->{'status'} ) {
    $status = 1;
  } else {
    $status = 0;
  } 
  my $role_tar = params->{'role'};
  my $uuid = params->{'uuid'};
  # updates user-fields
  database->quick_update('users', { user_uuid => $uuid }, {
      user_status => $status,
      user_role => $role_tar
    });
  redirect 'admin/users';
};

get '/user/delete/:uuid' => sub {
  if ( session('user') ) {
    database->quick_delete('users', { user_uuid => params->{'uuid'} });
  }
  redirect '/admin/users';
};

# handle group-changes etc.
get '/groups' => sub {
  my ($sql, $sth, @row);
  if ( session('role') eq 'admin' or session('role') eq 'teacher' ) {
    # select all groups
    $sql = "SELECT * FROM usergroups;";
    $sth = database->prepare($sql);
    $sth->execute();
    @row = $sth->fetchall_arrayref({}); 
    template 'groups_overview', {
      page_title => 'Groups Overview',
      row => \@row
    };
  } else {
    redirect '/';
  }
};

get '/group/new' => sub {
  if ( session('role') eq 'admin' or session('role') eq 'teacher' ) {
    template 'new_group', {
      page_title => "New Group",
    };
  } else {
    redirect '/admin';
  }
};

post '/group/new' => sub {
  if ( session('role') eq 'admin' or session('role') eq 'teacher' ) {
    my $group_slug = params->{'group_slug'};
    my $checkGroupSlug = database->quick_count('usergroups', { group_slug => $group_slug });
    if ( $checkGroupSlug > 0 ) {
      # Maybe this is not neccesary, but just in case ... its there
      my $error_msg = "This Groupname already exists.";
      template 'new_group', {
        page_title => "New Group",
        group_slug => $group_slug,
        error_msg => $error_msg
      };
    } else {
      # group gets created
      database->quick_insert('usergroups', {
          group_slug => $group_slug
        });
      redirect '/admin/groups';
    }
  } else {
    redirect '/';
  }
};

get '/group/delete/:id' => sub {
  if ( session('role') eq 'admin' or session('role') eq 'teacher' ) {
    database->quick_delete('usergroups', { gid => params->{'id'} });
    redirect '/admin/groups';
  } else {
    redirect '/';
  }
};

prefix undef;
