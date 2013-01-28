use strict;
use warnings;

use Test::More tests => 8;
BEGIN { use_ok('Easy::Template') };

use Easy::Template;

my $tmp = Easy::Template->new('t/template/test1.temp');

isa_ok($tmp,'Easy::Template');
can_ok($tmp,$_) for qw/param if output/;

$tmp->param(test => 'hello');

is($tmp->output,'hello','Replace string in template file');

my $new_tmp = $tmp->new('t/template/test2.temp');

isa_ok($tmp,'Easy::Template');

is($new_tmp->output ,"2\n",'Evaluate code in template file');

done_testing();
