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

prefix undef;
