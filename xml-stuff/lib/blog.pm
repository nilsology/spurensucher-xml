package blog;
use Dancer ':syntax';
use Dancer::Plugin::RequireSSL;
#use Dancer::Plugin::ProxyPath;
use Dancer::Plugin::Database;
use CGI;
use Crypt::SaltedHash;
use Data::UUID;
use DBI;
use POSIX qw(strftime);
use MIME::Lite;
use strict;
use warnings;
use feature qw{ switch };
our $VERSION = '0.1';
set behind_proxy => true;
require_ssl();

get '/' => sub {
  if ( ! session('user') ) {
    template 'login';
  }
};

load 'account_routes.pl', 'login_routes.pl', 'admin_routes.pl', 'blog_routes.pl', 'blog_display.pl', 'page_routes.pl';


true;