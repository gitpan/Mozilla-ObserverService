use strict;
use warnings FATAL => 'all';

use Test::More tests => 7;
use Mozilla::Mechanize;
use URI::file;
use File::Temp qw(tempdir);
use File::Slurp;

BEGIN { use_ok('Mozilla::ObserverService'); };

$ENV{HOME} = tempdir("/tmp/observice-XXXXXX", CLEANUP => 1);

my $pid = fork;
exec('perl t/one_time_http.pl t/test.html') if !$pid;

my $moz = Mozilla::Mechanize->new(quiet => 1, visible => 0);

my @_last_call = ('NONE');
is(Mozilla::ObserverService::Register({
	'http-on-examine-response' => sub { @_last_call = @_; },
}), 1);

my $url = read_file($ENV{HOME} . "/oth.url");
ok($moz->get($url));
is($moz->title, "Test-forms Page");
waitpid($pid, 0);

isnt($_last_call[0], 'NONE');
isa_ok($_last_call[0], 'Mozilla::ObserverService::nsIHttpChannel');
is($_last_call[0]->responseStatus, 200);

$moz->close();
