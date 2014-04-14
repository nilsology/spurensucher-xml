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

prefix '/account';

get '/' => sub {
  my $username = session('user');
  if ( session('user') ) {
    return redirect '/admin';
  } else {
    return redirect '/login';
  }
};

# sub to generate new user_uuid
sub UUID {
  my $ug = new Data::UUID;
  my $uuid = $ug->create();
  my $str = $ug->to_string( $uuid );
  return $str;
}

get '/register' => sub {
  template 'register', {
    page_title => 'Register as new user'
  };
};

post '/register' => sub {
  our ($username, $password, $email, $crypt, $shash, $salt, $uuid, $status, @chars, $tmp_token, $timestamp, $role, $sql, $sth, $error_msg);
  #from form
  $username = params->{'username'};
  $password = params->{'passphrase'};
  $email = params->{'email'};
  #generating salted hash and salt from password
  $crypt = Crypt::SaltedHash->new(algorithm=>'SHA-512');
  $crypt->add($password);
  $shash = $crypt->generate();
  $salt = $crypt->salt_hex();
  
  $uuid = UUID;
  $status = false;
  $timestamp = strftime "%Y-%m-%d %H:%M:%S", localtime;
  # chars used to generate token
  @chars = ("A".."Z", "a".."z");
  # standard role - can be changed later
  $role = 'editor';
  
  # check if username / email are already registerd
  sub checkCredentials {
    my ($result) = database->selectrow_array("SELECT count(*) FROM `users` WHERE user_name='$username' OR user_email='$email'");
    if ( $result ne 0) {
      return false;
    } else {
      return true;
    }
  }

  # sub to send confirmation email to user with a link incl. token
  sub confirmAccount {
    my $from = 'noreply@nilsology.net';
    my $subject = 'Confirm Account';
    my $msg = <<END;
Hello $username,
please visit the following link to confirm your account and activate it:

http://nilsology.net/account/confirm/activate/$tmp_token

If you didn't apply for this account just simply do NOT visit the provided link.
If there are any questions you are having just shoot me an email at info\@nilsology.net.

Cheers
END
    my $mail = MIME::Lite->new(
                          From    => $from,
                          To      => $email,
                          Subject => $subject,
                          Data    => $msg
                        );
    $mail->send;
  }

  if ( params->{'submit'} ) {
    if ( !$username or !$password or !$email ) {
      $error_msg = "Please fillout all required fields!";
      template 'register', {
        error => $error_msg,
        username => $username,
        email => $email,
        page_title => 'Register as new user'
      };
    } else {
      if ( checkCredentials eq true ) { 
        $tmp_token .= @chars[rand @chars] for 1..99;

        # escape strings
        $username =~ s/\\|\/\/|"|'//g;
        $email =~ s/\\|\/\/|"|'//g;

        #registers user
        database->quick_insert('users', {  
            user_uuid => $uuid,
            user_name => $username,
            user_saltedHash => $shash,
            user_salt => $salt,
            user_email => $email,
            user_create_date => $timestamp,
            user_status => $status,
            user_token => $tmp_token,
            user_role => $role
          });
        # send confirm-email
        confirmAccount;
        # unset token so next time it doesn't add up to itself
        undef $tmp_token;
        # tell user to check inbox
        $error_msg = "An email has been sent to `$email` for you to confirm this account.";
        template 'message', { error => $error_msg };
      } else {
        $error_msg = "This username or email has already been taken.";
        template 'register', { error => $error_msg, username => $username, email => $email };
      }
    }
    # if params->{'submit'} is not set redirect to register page
  } else {
    redirect '/account/register';
  }
};

get '/confirm/activate/:token' => sub {
  my $token = params->{'token'};
  # find row where :token occurs
  my $sql = "SELECT count(*), user_uuid FROM `users` WHERE user_token=?";
  my $sth = database->prepare($sql);
  $sth->execute($token) or die "SQL Error: $DBI::errstr\n";
  my @row = $sth->fetchrow_array;
  my $result = $row[0];
  my $uuid = $row[1];
  if ( $result eq 1 ) {
    #activates account and unsets token (to NULL)
    database->quick_update('users', { user_uuid => $uuid }, {
        user_status => true,
        user_token => 'NULL'
      });
    my $error_msg = "Your account has just been activated. You can now log in:";
    return template 'login', { error => $error_msg };
  } else {
    my $error_msg = "Your account could not be activated, please consult an admin.";
    return template 'message', { error => $error_msg };
  }
};

get '/delete' => sub {
    my ($uuid, $from, $subject, $msg, $mail, @chars, $sql, $sth, @row, $error_msg);
    our ($username, $email, $tmp_token);
  if ( session('user') ) {
    $username = session('user');
    $email = database->quick_lookup('users', { user_name => $username }, 'user_email');
    $uuid = database->quick_lookup('users', { user_name => $username }, 'user_uuid');
    $sql = $sth = undef;
    @chars = ("A".."Z", "a".."z");
    $tmp_token .= @chars[rand @chars] for 1..99;
    # set user_token
    database->quick_update('users', { user_uuid => $uuid }, { user_token => $tmp_token });
    # email to confirm deletion
    sub confirmDelete {
      my $from = 'noreply@nilsology.net';
      my $subject = 'Confirm your deletion request';
      my $msg = <<END;
Hello $username,
please visit the following link to confirm that you want your account to be deleted::

http://nilsology.net/account/confirm/delete/$tmp_token

If you do NOT want your account to be deleted just do NOT visit the provided link.
Cheers
END
      my $mail = MIME::Lite->new(
                            From    => $from,
                            To      => $email,
                            Subject => $subject,
                            Data    => $msg
                          );
      $mail->send;
    }
    # send confirmation email
    confirmDelete;
    undef $tmp_token;
    $error_msg = "An email has been sent to `$email` to confirm the deletion of your account";
    session->destroy;
    return template 'message', { error => $error_msg };
  } else {
    $error_msg = "To delete your account you have to login first.";
    session->destroy;
    return template 'login', { error => $error_msg };
  } 
};

get '/confirm/delete/:token' => sub {
  my ($uuid, $username, $result, @row, $token, $sql, $sth, $error_msg);
  $username = session('user');
  $token = params->{'token'};
  # find row in which :token occurs
  $sql = "SELECT count(*), user_uuid, user_name FROM `users` WHERE user_token=?;";
  $sth = database->prepare($sql);
  $sth->execute($token) or die "SQL Error: $DBI::errstr\n";
  @row = $sth->fetchrow_array;
  $result = $row[0];
  $uuid = $row[1];
  $username = $row[2];
  $sql = $sth = undef;
  if ( $result eq 1 ) {
    $sql = "DELETE FROM `users` WHERE user_uuid=?;";
    $sth = database->prepare($sql);
    $sth->execute($uuid) or die "SQL Error: $DBI::errstr\n";
    session->destroy;
    $error_msg = "Your account has been deleted successfully!";
  } else {
    $error_msg = "Your account could not be deleted, please consult an admin.";
  }
  if ( session('user') ) {
    session->destroy;
  }
  return template 'message', { error => $error_msg };
};

# change password
get '/pwd_chg' => sub {
  my $error_msg;
  if ( session('user') ) {
    $error_msg = "Please type in your new password.";
    return template 'pwd_chg', {
      error => $error_msg,
      page_title => 'Change Password'
    };
  } else {
    $error_msg = "Please log in first to change your password.";
    return template 'login', { error => $error_msg }; 
  }
};

post '/pwd_chg' => sub {
  my ($username, $crypt, $password, $shash, $salt, $sql, $sth, $error_msg);
  if ( session('user') ) {
    if ( ! params->{'passphrase'} ) {
      $error_msg = "If you want to change your password you eventually have to type in a password. I admit it is tricky.";
      return template 'pwd_chg', {
        error => $error_msg,
        page_title => 'Change Password'
      };
    }
    $password = params->{'passphrase'};
    $username = session('user');
    #generating salted hash and salt from password
    $crypt = Crypt::SaltedHash->new(algorithm=>'SHA-512');
    $crypt->add($password);
    $shash = $crypt->generate();
    $salt = $crypt->salt_hex();
    # writing new values(saltedHash, salt) to db
    $sql = "UPDATE `users` SET user_saltedHash=?, user_salt=? WHERE user_name=?;";
    $sth = database->prepare($sql);
    $sth->execute($shash, $salt, $username) or die "SQL Error: $DBI::errstr\n";
    $error_msg = "Your password has been changed successfully!";
  } else {
    $error_msg = "Please log in first to change your password.";
  }
  # requires login
  session->destroy;
  return template 'login', { error => $error_msg };
};

get '/pwd_lost' => sub {
  my $error_msg = "Please type in your email adress:";
  if ( session('user') ) {
    session->destroy;
  } 
  template 'lost_pwd', {
    error => $error_msg,
    page_title => 'Lost Password? Recover with your email.'
  };
};

post '/pwd_lost' => sub {
  my ($uuid, @chars, $sql, $sth, @row, $result, $error_msg);
  our ($email, $username, $tmp_token);
  $email = params->{'email'};
  $sql = "SELECT count(*), user_uuid, user_name FROM `users` WHERE user_email=?;";
  $sth = database->prepare($sql);
  $sth->execute($email) or die "SQL Error: $DBI::errstr\n";
  @row = $sth->fetchrow_array;
  $result = $row[0];
  $uuid = $row[1];
  $username = $row[2];
  $sql = $sth = undef;
  @chars = ("A".."Z", "a".."z");
  # email for password-recovery
  sub changePWD {
    my $from = 'noreply@nilsology.net';
    my $subject = 'Password Recovery';
    my $msg = <<END;
Hello $username,
please visit the following link if you want to recover your password:

http://nilsology.net/account/pwd_recv/$tmp_token

If you do NOT want to recover your password just do NOT follow the provided link.
Cheers
END
    my $mail = MIME::Lite->new(
      From    => $from,
      To      => $email,
      Subject => $subject,
      Data    => $msg
    );
    $mail->send;
  }

  if ( $result eq 1 ) {
    $tmp_token .= @chars[rand @chars] for 1..99; 
    # write token to db
    $sql = "UPDATE `users` SET user_token='$tmp_token' WHERE user_uuid=?;";
    $sth = database->prepare($sql);
    $sth->execute($uuid) or die "SQL Error: $DBI::errstr\n";
    changePWD;
    undef $tmp_token;
    $error_msg = "An email has been sent to `$email` with a recovery-link.";
    return template 'message', { error => $error_msg };
  } else {
    $error_msg = "There is no account with this email.";
    return template 'lost_pwd', {
      error => $error_msg,
      page_title => 'Lost Password? Recover with your email.'
    };
  }
};

# is required somehow ... do not delete
get '/pwd_recv' => sub {
  return 1;
};

get '/pwd_recv/:token' => sub {
  my $error_msg = "Please type in your new password and do not forget it again.";
  my $token = params->{'token'};
  template 'pwd_recv', {
    error => $error_msg,
    token => $token,
    page_title => 'Recover Password'
  };
};

post '/pwd_recv' => sub {
  my ($token, $password, $sql, $sth, $error_msg, @row, $result, $uuid, $crypt, $shash, $salt);
  $token = params->{'token'};
  if ( ! params->{'passphrase'} ) {
    $error_msg = "If you want to recover your password you eventually have to type in a password. I admit it is tricky.";
    return template 'pwd_recv', { error => $error_msg };
  }
  $password = params->{'passphrase'};
  $sql = "SELECT count(*), user_uuid, user_name FROM `users` WHERE user_token=?;";
  $sth = database->prepare($sql);
  $sth->execute($token) or die "SQL Error: $DBI::errstr\n";
  @row = $sth->fetchrow_array;
  $result = $row[0];
  $uuid = $row[1];
  $sql = $sth = undef;
  #generating salted hash and salt from password
  $crypt = Crypt::SaltedHash->new(algorithm=>'SHA-512');
  $crypt->add($password);
  $shash = $crypt->generate();
  $salt = $crypt->salt_hex();
  # write new values (saltedHash, salt) to db
  $sql = "UPDATE `users` SET user_saltedHash=?, user_salt=?, user_token=NULL WHERE user_uuid=?;";
  $sth = database->prepare($sql);
  $sth->execute($shash, $salt, $uuid) or die "SQL Error: $DBI::errstr\n";
  $error_msg = "Your password has been changed successfully!";
  # provide page with notice and link to login again
  return template 'message', { error => $error_msg, msg_link => 'http://nilsology.net/login', msg_link_text => 'Log In' };
};

prefix undef;
