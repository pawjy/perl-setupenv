use inc::Module::Install;
name 'Hoge';
all_from 'lib/Hoge.pm';
readme_from 'lib/Hoge.pm';
readme_markdown_from 'lib/Hoge.pm';
githubmeta;

requires 'Class::Accessor::Fast';

tests 't/*.t';
author_tests 'xt';

install_script 'bin/hoge';

build_requires 'Test::Differences';
auto_set_repository;
WriteAll;
