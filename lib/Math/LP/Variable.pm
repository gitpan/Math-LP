package Math::LP::Variable;
use strict;
use Math::LP::Object;
use base qw(Math::LP::Object);
use fields(
    'name',   # a string, required
    'is_int', # flags whether it is an integer variable, defaults to false
    'value',  # numerical value, optional
    'index',  # column index in an LP, used by the Math::LP functions
);

sub initialize {
    my Math::LP::Variable $this = shift;
    defined($this->{name}) or 
	$this->croak("No name given for Math::LP::Variable");
    $this->{is_int} ||= 0;
}

1;

__END__

=head1 NAME

Math::LP::Variable - variables used in linear programs

=head1 SYNOPSIS

    use Math::LP::Variable;

    # make a variable named x1
    my $x1 = new Math::LP::Variable(name => 'x1');

    # make an integer variable named x2
    my $x2 = new Math::LP::Variable(name => 'x2', is_int => 1);

    # make a variable named x3 initialized to 3.1415
    my $x3 = new Math::LP::Variable(name => 'x3', value => '3.1415');

=head1 DESCRIPTION

=head2 DATA FIELDS

=over 4

=item name

a string with the name of the variable (required)

=item is_int

a flag indicating whether the variable can only have integer values
(optional, defaults to false)

=item value

a number representing the value of the variable (optional)

=item index

an integer number holding the index of the variable in the matrix of the
LP the variable is used in (optional)

=back

=head2 METHODS

No methods available.

=head1 SEE ALSO

L<Math::LP> and L<Math::LP::Object>

=head1 AUTHOR

Wim Verhaegen E<lt>wim.verhaegen@ieee.orgE<gt>

=head1 COPYRIGHT

Copyright(c) 2000 Wim Verhaegen. All rights reserved. 
This program is free software; you can redistribute
and/or modify it under the same terms as Perl itself.

=cut

