use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'	   => 'Math::LP',
    ($] > 5.004) ? (
      'ABSTRACT'  => 'OO approach to solving linear problems (interfaces to Math::LP::Solve)',
      'AUTHOR'    => 'Wim Verhaegen <wim.verhaegen@ieee.org>',
    ) : (),
    'PREREQ_PM'    => { 'Math::LP::Solve' => '3.02' },
    'VERSION_FROM' => 'lib/Math/LP.pm', 
    'clean'        => {
	FILES => '*/*/*/*~ */*/*/*/*~ */*/*/*/*/*~ */*/*/*/*/*/*~'
     },
    'dist'         => { 
	CI        => 'cvs ci',
	RCS_LABEL => 'cvs tag Math-LP-$(VERSION_SYM)' 
     }, 
);

