package Math::LP::LinearCombination;
use strict;
use Math::LP::Object;
use Math::LP::Variable;
use base qw(Math::LP::Object);
use fields(
    'vars_with_coeffs', # array with entry of type:
	                #   ref to hash with elements:
	                #     var   => Math::LP::Variable object
                        #     coeff => numerical coefficient
    'value', # cached value
);

sub initialize {
    my Math::LP::LinearCombination $this = shift;
    $this->{vars_with_coeffs} ||= [];
}
sub add_var_with_coeff {
    my Math::LP::LinearCombination $this = shift;
    my ($var,$coeff) = @_;
    push @{$this->{vars_with_coeffs}}, {var => $var, coeff => $coeff};
}
sub make { # short alternative to new()
    my $pkg = shift;
    my $ra_args = \@_;
    if(defined($ra_args->[0]) 
       && defined(ref $ra_args->[0]) 
       && ref($ra_args->[0]) eq 'ARRAY') {
	$ra_args = $ra_args->[0]; # argument array was passed as a ref
    };
    my $this = new $pkg;
    while(@$ra_args) {
	my $var = shift @$ra_args;
	defined(my $coeff = shift @$ra_args) or die "Odd number of arguments";
	$this->add_var_with_coeff($var,$coeff);
    }
    return $this;
}
sub calculate_value { # calculates the value, and caches it in the value field
    my Math::LP::LinearCombination $this = shift;

    my $val = 0;
    foreach(@{$this->{vars_with_coeffs}}) {
	$val += $_->{var}->{value} * $_->{coeff}; # this will fail on undefined variable values!
    }

    return $this->{value} = $val;
}
1;

__END__

=head1 NAME

Math::LP::LinearCombination - linear combination of Math::LP::Variable objects

=head1 SYNOPSIS

    use Math::LP::LinearCombination;

    # first construct some variables
    $x1 = new Math::LP::Variable(name => 'x1');
    $x2 = new Math::LP::Variable(name => 'x2');

    # build x1 + 2 x2 from an empty linear combination
    $lc1 = new Math::LP::LinearCombination;
    $lc1->add_var_with_coeff($x1,1.0);
    $lc1->add_var_with_coeff($x2,2.0);

    # alternatively, make x1 + 2 x2 in one go
    $lc2 = make Math::LP::LinearCombination($x1, 1.0,
                                            $x2, 2.0 );

=head1 DESCRIPTION

Any client should not access any other field than the C<value> field.
This field contains the value of the linear combination, typically
obtained in calculate_value(), but it may be set elsewhere (e.g. by
the solve() function in Math::LP).

The following methods are available:

=over 4

=item new()

returns a new, empty linear combination

=item make($var1,$coeff1,$var2,$coeff2,...)

returns a new linear combination initialized with the given variables and
coefficients. A ref to an array of variables and coefficients is also
accepted as a legal argument.

=item add_var_with_coeff($var,$coeff)

adds a variable to the linear combination with the given coefficient

=item calculate_value()

calculates the value of the linear combination. The value is also stored in the
C<value> field. Requires that the values of all variables are defined.

=back

=head1 SEE ALSO

L<Math::LP::Object> and L<Math::LP::Variable>

=head1 AUTHOR

Wim Verhaegen E<lt>wim.verhaegen@ieee.orgE<gt>

=head1 COPYRIGHT

Copyright(c) 2000 Wim Verhaegen. All rights reserved. 
This program is free software; you can redistribute
and/or modify it under the same terms as Perl itself.

=cut


