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

get '/collections' => sub {

  my ($sql, $sth, @row, @counts); 

  $sql = "SELECT taskcollections.tcid, tc_title FROM taskcollections;";
  $sth = database->prepare($sql);
  $sth->execute;
  @row = $sth->fetchall_arrayref({});
  
  # count people in group - not yet implemented
  $sql = "SELECT tcid, count(tid) AS amount FROM taskcollections_tasks GROUP BY tcid;";
  $sth = database->prepare($sql);
  $sth->execute();
  @counts = $sth->fetchall_arrayref({});
  
  template 'tc_overview', {
    page_title => "Collection Overview",
    row => \@row,
    counts => \@counts
  };
};

get '/collections/my' => sub {

  my ($sql, $sth, @row, @counts); 
  my $uuid = database->quick_lookup('users', { user_name => session('user') }, 'user_uuid');

  $sql = "SELECT taskcollections.tcid, tc_title FROM taskcollections JOIN user_taskcollections ON user_taskcollections.tcid = taskcollections.tcid AND user_taskcollections.uuid = \"$uuid\";";
  $sth = database->prepare($sql);
  $sth->execute;
  @row = $sth->fetchall_arrayref({});
  
  # count people in group - not yet implemented
  $sql = "SELECT tcid, count(tid) AS amount FROM taskcollections_tasks GROUP BY tcid;";
  $sth = database->prepare($sql);
  $sth->execute();
  @counts = $sth->fetchall_arrayref({});
  
  template 'tc_overview', {
    page_title => "My Collections",
    row => \@row,
    counts => \@counts
  };
};

get '/collection/new' => sub {
  template 'tc_new', {
    page_title => 'New Collection'
  };
};

post '/collection/new' => sub {
  my $uuid = database->quick_lookup('users', { user_name => session('user') }, 'user_uuid');
  my $title = params->{'title'};

  my $ifExist = database->quick_count('taskcollections', { tc_title => $title });

  if ( $ifExist == 0 ) {

    database->quick_insert('taskcollections', {
        tc_title => $title
      });

    my $tcid = database->quick_lookup('taskcollections', { tc_title => $title }, 'tcid');

    database->quick_insert('user_taskcollections', {
        tcid => $tcid,
        uuid => $uuid
      });

    redirect "/admin/collection/$tcid";
      
  } else {
    
    template 'tc_new', {
      page_title => 'New Collection',
      error_msg => 'Title already exists.',
      title => $title 
    };

  }
};

get '/collection/:tcid' => sub {
  my ($sql, $sth, @row);

  my $tcid = params->{'tcid'};
  my $role = session('role');
  my $ifAllowed = database->quick_lookup('user_taskcollections', { tcid => $tcid }, 'uuid');
  my $uuid = database->quick_lookup('users', { user_name => session('user') }, 'user_uuid');
  if ( $ifAllowed eq $uuid or $role eq 'teacher' or $role eq 'admin' ) {

    # selecting all tasks (+ items) associated with the task_collection with the tcid of :tcid
#    $sql = "SELECT tasks.tid, t_index, t_text, t_score FROM tasks JOIN taskcollections_tasks ON taskcollections_tasks.tcid = ? ORDER BY t_index;";
    $sql = "SELECT tasks.tid, t_index, t_text, t_score FROM tasks JOIN taskcollections_tasks ON taskcollections_tasks.tcid = ? AND taskcollections_tasks.tid = tasks.tid ORDER BY t_index;";
    $sth = database->prepare($sql);
    $sth->execute($tcid);
    @row = $sth->fetchall_arrayref({});
    
    # selecting username associated (through $user_uuid) with tc
    my $username = database->quick_lookup('users', { user_uuid => $ifAllowed }, 'user_name');

    # selecting information about the taskcollection 
    my $tc_title = database->quick_lookup('taskcollections', { tcid => $tcid }, 'tc_title');

    template 'tc_single', {
      row => \@row,
      username => $username,
      tc_title => $tc_title,
      tcid => $tcid,
      page_title => "Overview '$tc_title'"
    };
    
  } else {
    redirect '/admin/collections';
  }
};

get '/collection/edit/:tcid' => sub {
  
  my $tcid = params->{'tcid'};
  my $role = session('role');
  my $ifAllowed = database->quick_lookup('user_taskcollections', { tcid => $tcid }, 'uuid');
  my $uuid = database->quick_lookup('users', { user_name => session('user') }, 'user_uuid');
  if ( $ifAllowed eq $uuid or $role eq 'teacher' or $role eq 'admin' ) {

    # selecting information about the taskcollection 
    my $tc_title = database->quick_lookup('taskcollections', { tcid => $tcid }, 'tc_title');
    
    template 'tc_edit', {
      tc_title => $tc_title,
      tcid => $tcid,
      page_title => "Edit $tc_title"
    };
    
  } else {
    redirect "/admin/collection/$tcid";
  }
};

post '/collection/edit' => sub {
  
  my $tcid = params->{'tcid'};
  my $tc_title = params->{'tc_title'};

  database->quick_update('taskcollections', { tcid => $tcid }, { tc_title => $tc_title });

  redirect "/admin/collection/$tcid";
};

get '/collection/delete/:tcid' => sub {

  # later when the rest is implemented

};

get '/task/new/:tcid' => sub {
  template 'task_new', {
    page_title => 'New Task',
    tcid => params->{'tcid'}
  };
};

post '/task/new' => sub {
  
  my $t_text = params->{'t_text'};
  my $t_index = params->{'t_index'};
  my $t_score = params->{'t_score'};
  my $tcid = params->{'tcid'};

  database->quick_insert('tasks', {
      t_text => $t_text,
      t_index => $t_index,
      t_score => $t_score
    });

  my $tid = database->{mysql_insertid};

  database->quick_insert('taskcollections_tasks', {
      tcid => $tcid,
      tid => $tid
    });

  redirect "/admin/collection/$tcid";
  
};

get '/task/edit/:tid/:tcid' => sub {
  my $tid = params->{'tid'};
  my $tcid = params->{'tcid'};

  template 'task_edit', {
    page_title => 'Edit Task',
    tid => $tid,
    tcid => $tcid,
    t_text => database->quick_lookup('tasks', { tid => $tid }, 't_text'), 
    t_score => database->quick_lookup('tasks', { tid => $tid }, 't_score'), 
    t_index => database->quick_lookup('tasks', { tid => $tid }, 't_index') 
  };
};

post '/task/edit' => sub {
  my $tid = params->{'tid'};
  my $tcid = params->{'tcid'};
  my $t_text = params->{'t_text'};
  my $t_score = params->{'t_score'};
  my $t_index = params->{'t_index'};

  database->quick_update('tasks', { tid => $tid }, {
      t_text => $t_text,
      t_score => $t_score,
      t_index => $t_index
    });

  redirect "/admin/collection/$tcid";

};

get '/task/delete/:id' => sub {

  # later when the rest is implemented

};

get '/task/:id' => sub {

  # should display the associated hints
  # after Hints are implemented


};


prefix undef;
