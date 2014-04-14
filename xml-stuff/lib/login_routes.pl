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

hook 'before' => sub {
  if ( ! session('user') and request->path_info =~ m{^/admin} ) {
    var requested_path => request->path_info;
    request->path_info('/login');
  }
};

get '/login' => sub {
  if ( session('user') ) {
    redirect uri_for('/admin');
  }
  template 'login', { path => vars->{requested_path} };
};

post '/login' => sub {
  my ($username, $password, $sql, $sth, @row, $crypt, $verified, $shash, $status, $error_msg, $cgi, $session, $cookie, $role, $uuid);
  $username = params->{'username'};
  $password = params->{'passphrase'};

  if ( !$username or !$password ) {
    $error_msg = "Please provide a username and password.";
    return template 'login', { error => $error_msg, username => $username };
  }

  # select values to either later store in sessions or use now to validate login-credentials
  $sql = "SELECT user_saltedHash, user_status, user_role, user_uuid FROM `users` WHERE user_name=?;";
  $sth = database->prepare($sql);
  $sth->execute($username) or die "SQL Error: $DBI::errstr\n";
  unless ( $sth->rows ) {
    $error_msg = "Username is incorrect.";
    return template 'login', { error => $error_msg };
  }

  @row = $sth->fetchrow_array;
  $shash = $row[0];
  $status = $row[1];
  $role = $row[2];
  $uuid = $row[3];
  $crypt = Crypt::SaltedHash->new(algorithm=>'SHA-512');
  # verify entered password and compare with saltedHash from db
  $verified = $crypt->validate($shash, $password);
  
  #check if account is activated
  if ( $status eq 0 ) {
    $error_msg = "Account is not activated.";
  } else {
    if ( $verified eq 1 ) {
      # set a few session parameters
      session user => $username;
      session role => $role;
      session uuid => $uuid;
      redirect params->{'path'} || '/admin';
    } else {
      $error_msg = "Password is incorrect!";
    }
  }

  template 'login', { error => $error_msg, username => $username };
};

get '/logout' => sub {
  if ( ! session('user') ) {
    return redirect '/login';
  }
  # destroy session to logout
  session->destroy;
  redirect '/login';
};
