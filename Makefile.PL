use inc::Module::Install;
name 'PlackX-Request';
all_from 'lib/PlackX/Request.pm';

# requires '';

tests 't/*.t';
author_tests 'xt';

build_requires 'Test::More';
use_test_base;
auto_include;
WriteAll;
