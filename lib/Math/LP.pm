package Math::LP;
use strict;
use Exporter;
use Math::LP::Constraint;
use Math::LP::Solve;
our(@EXPORT,@EXPORT_OK,%EXPORT_TAGS, # Exporter related
    $MAX,$MIN,   # objective function types
    $OPTIMAL,$MILP_FAIL,$INFEASIBLE,$UNBOUNDED,$FAILURE,$RUNNING, 
    $FEAS_FOUND,$NO_FEAS_FOUND,$BREAK_BB, # possible status values after solve 
    $VERSION,
    );
use base qw(Math::LP::Object Exporter);
use fields (
    'solver_status',      # status after solve() is called
    'variables',          # hash of variables used in this LP
    'constraints',        # array of constraints in this LP
    'objective_function', # Math::LP::LinearCombination object
    'type',               # either $MAX or $MIN
    '_dbuf',              # doublePtr (wrapper for double*) buffer used internally for passing data to lprec structs
    '_dbufsize',          #  and its size
);
$VERSION = '0.01';

# only the package variables are made available for exporting
@EXPORT = qw();
%EXPORT_TAGS = (
    types         => [qw($MAX $MIN)],
    solver_status => [qw($OPTIMAL $MILP_FAIL $INFEASIBLE $UNBOUNDED $RUNNING
			 $FEAS_FOUND $NO_FEAS_FOUND $BREAK_BB)],
);
$EXPORT_TAGS{all} = [@{$EXPORT_TAGS{types}},
		     @{$EXPORT_TAGS{solver_status}}];
@EXPORT_OK = @{$EXPORT_TAGS{all}};

BEGIN {
    # objective function types (not defined by LP_Solve)
    $MAX = 0;
    $MIN = 1;
    
    # solver states (exit states of LP_Solve's solve() and lag_solve())
    $OPTIMAL         = $Math::LP::Solve::OPTIMAL;
    $MILP_FAIL       = $Math::LP::Solve::MILP_FAIL;
    $INFEASIBLE      = $Math::LP::Solve::INFEASIBLE;
    $UNBOUNDED       = $Math::LP::Solve::UNBOUNDED;
    $FAILURE         = $Math::LP::Solve::FAILURE;
    $RUNNING         = $Math::LP::Solve::RUNNING;
    $FEAS_FOUND      = $Math::LP::Solve::FEAS_FOUND;
    $NO_FEAS_FOUND   = $Math::LP::Solve::NO_FEAS_FOUND;
    $BREAK_BB        = $Math::LP::Solve::BREAK_BB;
}

### Object setup
sub initialize {
    my Math::LP $this = shift;
    $this->{variables} ||= {};
    $this->{constraints} ||= [];
    $this->{_dbufsize} ||= 32;
    $this->{_dbuf} = Math::LP::Solve::ptrcreate('double',0.0,$this->{_dbufsize});
}
sub DESTROY {
    my Math::LP $this = shift;
    Math::LP::Solve::ptrfree($this->{_dbuf});
}

### Memory handling
sub get_dbuf { # with dynamic buffer management
    my Math::LP $this = shift;
    my $size = shift;
    my $initval = shift || 0.0;

    # update buffer size if needed
    if($this->{_dbufsize} < $size) {
	Math::LP::Solve::ptrfree($this->{_dbuf});
	while($this->{_dbufsize} < $size) {
	    $this->{_dbufsize} *= 2;
	}
	$this->{_dbuf} = Math::LP::Solve::ptrcreate('double',0.0,$this->{_dbufsize});
    }

    # initialize the buffer
    for(my $i = 0; $i < $size; ++$i) {
	Math::LP::Solve::ptrset($this->{_dbuf},$initval,$i);
    }
    
    return $this->{_dbuf};
}

### Manipulation of the LP
sub nr_rows { # == nr constraints
    my Math::LP $this = shift;
    return scalar @{$this->{constraints}};
}
sub nr_cols { # == nr variables
    my Math::LP $this = shift;
    return scalar keys %{$this->{variables}};
}
sub add_variable { # assigns an index to new variables, returns the variable's index
    my Math::LP           $this = shift;
    my Math::LP::Variable $var  = shift;
    unless(exists $this->{variables}->{$var->{name}}) { # new variable
	$this->{variables}->{$var->{name}} = $var; # registers the variable
	$var->{index} = $this->nr_cols(); # first variable gets 1, second 2, ...
    }
    return $var->{index};
}
sub add_constraint { # does what it says, implicitly adds all the variables
    my Math::LP             $this   = shift;
    my Math::LP::Constraint $constr = shift;

    # register all variables present in the constraint
    foreach(@{$constr->{lhs}->{vars_with_coeffs}}) {
	$this->add_variable($_->{var});
    }

    # register the constraint
    push @{$this->{constraints}}, $constr;
    $constr->{index} = $this->nr_rows();

    return $constr->{index};
}
sub set_objective_function {
    my Math::LP $this = shift;

    # initialize the objective function and type
    $this->{objective_function} = shift;
    $this->{type} = shift;
    
    # register all variables in the objective function
    foreach(@{$this->{objective_function}->{vars_with_coeffs}}) {
	$this->add_variable($_->{var});
    }
}
sub maximize_for { 
    $_[0]->set_objective_function($_[1],$MAX);
}
sub minimize_for { 
    $_[0]->set_objective_function($_[1],$MIN);
}

### Solving the LP
sub solve {
    my Math::LP $this = shift;
    my $lag_solve = shift || 0; # lag_solve flag

    # 1. construct an equivalent lprec struct
    my $lprec = $this->make_lprec();
    
    # 2. solve the LP
    $this->{solver_status} = $lag_solve 
        ? Math::LP::Solve::lag_solve($lprec)
	: Math::LP::Solve::solve($lprec);

    # 3. copy the results to the appropriate Math::LP objects
    $this->update_variable_values($lprec);
    $this->update_slacks($lprec);
    $this->update_dual_values($lprec);

    # 4. delete the lprec struct
    Math::LP::Solve::delete_lp($lprec);

    # 5. return true iff succeeded
    return $this->{solver_status} == $OPTIMAL; 
        # I am not sure whether this is the wanted behaviour for $lag_solve == 1
}
sub make_coeff_array {
    my Math::LP                    $this = shift;
    my Math::LP::LinearCombination $lc   = shift;

    # get a zero-initialized coefficient buffer
    my $array = $this->get_dbuf($this->nr_cols() + 1, 0.0); 
        # +1 for the 0'th column, which does not represent a variable

    # fill out the coefficients
    foreach(@{$lc->{vars_with_coeffs}}) {
        Math::LP::Solve::ptrset($array,$_->{coeff},$_->{var}->{index});
    }

    return $array;
}
sub make_lprec { # construct an lprec struct for the LP
    my Math::LP $this = shift;
    my $lprec = Math::LP::Solve::make_lp(0,$this->nr_cols()); # no constraints yet, correct nr. of variables
    
    # add the constraints
    foreach my $constr (@{$this->{constraints}}) {
        Math::LP::Solve::add_constraint($lprec,$this->make_coeff_array($constr->{lhs}),$constr->{type},$constr->{rhs});

	# Setting of the row name is disabled: it is not needed
        #Math::LP::Solve::lprec_row_name_set($lprec,$constr->{index},$constr->{name})
	#    if defined $constr->{name};
    }

    # mark the integer variables 
    foreach my $var (values %{$this->{variables}}) {
        Math::LP::Solve::set_int($lprec,$var->{index},1) if $var->{is_int};

	# Setting of the col name is disabled: it is not needed and triggered a bug I still do not understand
	#Math::LP::Solve::lprec_col_name_set($lprec,$var->{index},$var->{name});
    }

    # set the objective function
    if(defined($this->{objective_function})) {
        Math::LP::Solve::set_obj_fn($lprec,$this->make_coeff_array($this->{objective_function}));
	if   ($this->{type} == $MAX) { Math::LP::Solve::set_maxim($lprec); }
	elsif($this->{type} == $MIN) { Math::LP::Solve::set_minim($lprec); }
	else {
	    $this->croak('No objective function type ($MAX or $MIN) set for solving');
	}
    }
    
    return $lprec;
}
sub update_variable_values { # copies the variable values to the variable objects
    my Math::LP $this = shift;
    my $lprec = shift;
    
    # the variable values are found in the solution vector
    my $solution = Math::LP::Solve::lprec_best_solution_get($lprec);

    # The index offset is explained as follows
    #   + 1          because of the objective function value
    #   + nr_rows()  because of the slacks
    #   - 1          because the 1st variable has index 1, not 0
    my $offset = $this->nr_rows(); 

    # copy the appropriate value for each variable
    foreach(values %{$this->{variables}}) {
	my $var_index = $_->{index};
	$_->{value} = Math::LP::Solve::ptrvalue($solution,$offset+$var_index);
    }
}
sub update_slacks {
    my Math::LP $this = shift;
    my $lprec = shift;
    
    # the slacks are fetched from the solution vector
    my $solution = Math::LP::Solve::lprec_best_solution_get($lprec);

    # copy the appropriate slack for each constraint
    foreach(@{$this->{constraints}}) {
	my $row_index = $_->{index};

	# The net offset used for fetching the row slack is calculated as follows:
	#   + 1 because of the objective function value
	#   - 1 because the 1st row has index 1, not 0
	my $buggy_slack = Math::LP::Solve::ptrvalue($solution,$row_index);

	# Due to a bug (?), lp_solve does not return the slack for each
	# constraint, but the evaluation of the lhs for the optimal variable
	# values.
	$_->{lhs}->{value} = $buggy_slack;

        # The real slack is easily derived from the lhs value.
	$_->{slack} = $_->{rhs} - $buggy_slack;
    }

    # Also fetch the objective function value
    if(defined($this->{objective_function})) {
	$this->{objective_function}->{value} = Math::LP::Solve::ptrvalue($solution,0);
    }
}
sub update_dual_values {
    my Math::LP $this = shift;
    my $lprec = shift;

    # the dual values are fetched from the duals vector
    my $duals = Math::LP::Solve::lprec_duals_get($lprec);

    # copy the appropriate dual value for each constraint
    foreach(@{$this->{constraints}}) {
	my $row_index = $_->{index};
	$_->{dual_value} = Math::LP::Solve::ptrvalue($duals,$row_index)
    }
}

### Solution queries
sub optimum {
    my Math::LP $this = shift;
    return undef if !defined($this->{objective_function});
    return $this->{objective_function}->{value};
}

1;

__END__

=head1 NAME

Math::LP - Object oriented interface to solving of linear programs using the
lp_solve library

=head1 SYNOPSIS

    use Math::LP qw(:types);             # imports optimization types
    use Math::LP::Constraint qw(:types); # imports constraint types

    # make a new LP
    $lp = new Math::LP;

    # make the variables for the LP
    $x1 = new Math::LP::Variable(name => 'x1');
    $x2 = new Math::LP::Variable(name => 'x2');

    # maximize the objective function to x1 + 2 x2
    $obj_fn = make Math::LP::LinearCombination($x1,1.0,$x2,2.0);  
    $lp->maximize_for($obj_fn);

    # add the constraint x1 + x2 <= 2
    $constr = new Math::LP::Constraint(
        lhs  => make Math::LP::LinearCombination($x1,1.0,$x2,1.0),
        rhs  => 2.0,
        type => $LE,
    );
    $lp->add_constraint($constr);
 
    # solve the LP and print the results
    $lp->solve() or die "Could not solve the LP";
    print "Optimum = ", $obj_fn->{value}, "\n";
    print "x1 = ", $x1->{value}, "\n";
    print "x2 = ", $x1->{value}, "\n";
    print "slack = ", $constr->{slack}, "\n";

=head1 DESCRIPTION

The Math::LP package provides an object oriented interface to defining
and solving mixed linear/integer programs. It uses the lp_solve library
as the underlying solver. Please note that this is not a two way
relation. An LP is defined using Math::LP, converted to an lp_solve
data structure, and solved with lp_solve functions. It is not possible
to grab an lp_solve structure somehow and convert it to a Math::LP
object for manipulation and inspection. If you want to do that kind
of stuff in Perl, use the Math::LP::Solve package instead.

That being said, the logical way of constructing an LP consists of

=over 4

=item 1

Construct Math::LP::Variable objects, in the meanwhile marking integer variables

=item 2

Construct Math::LP::LinearCombination objects with the variables
and use them as the objective function and constraints

=item 3

Solve the LP

=item 4

Fetch the variable values from the Math::LP::Variable objects,
the slacks and dual values from the Math::LP::Constraint objects.
and the row values (including the optimum) from the corresponding
Math::LP::LinearCombination.

=back

=head1 DATA FIELDS

=over 4

=item solver_status

Holds the status of the last solve() call.
Can be either $OPTIMAL, $MILP_FAIL, $INFEASIBLE, $UNBOUNDED,
$FAILURE, $RUNNING, $FEAS_FOUND, $NO_FEAS_FOUND or $BREAK_BB.

=item variables

A ref to a hash with all the Math::LP::Variable objects used in
the LP indexed on their name.

=item constraints

A ref to an array with all Math::LP::Constraint objects used
in the LP.

=item objective_function

A Math::LP::LinearCombination object representing the objective function

=item type

The optimization type. Can be either $MAX or $MIN.

=back

=head1 METHODS

=over 4

=item new()

returns a new, empty LP

=item nr_rows()

returns the number of rows, i.e. the number of constraints in the LP

=item nr_cols()

returns the number of columns, i.e. the number of variables in the LP

=item add_variable($var)

registers the variable as belonging to the LP. The C<index> field of
the variable is set as a side effect. For this reason it is not allowed
to use 1 variable in 2 LP objects.

=item add_constraint($constr)

adds a Math::LP::Constraint to the LP. The C<index> field of the constraint
is likewise set. It is thus also not allowed to use a single constraint in
more than 1 LP. All variables present in the constraint are automatically
registered.

=item set_objective_function($lincomb,$type)

sets the objective function of the LP, specified by the following parameters:

=over 2

=item $lincomb

a Math::LP::LinearCombination forming the objective function.
New variables in the linear combination are automatically added to the LP.

=item $type

the optimization type, either $MAX or $MIN

=back

=item maximize_for($lincomb)

shortcut for set_objective_function($lincomb,$MAX)

=item minimize_for($lincomb)

shortcut for set_objective_function($lincomb,$MIN)

=item solve([$lag_solve])

Solves the LP, returns true if succeeded (i.e. the status value is $OPTIMAL),
false otherwise. The status of the solver is available in the C<status> field
afterwards. The default is to solve using solve(). If however $lag_solve is
specified and true, lag_solve() will be used.

=item optimum()

Returns the value of the objective function obtained by the solver.

=back

=head1 SEE ALSO

More info on the packages used in Math::LP is found in L<Math::LP::Object>,
L<Math::LP::Variable> and L<Math::LP::LinearCombination>.

The underlying wrapper to the lp_solve library is documented in
L<Math::LP::Solve>. More info on using the lp_solve library written
by Michel Berkelaar and adapted by Jeroen Dirks is found in its source 
code available from ftp://ftp.ics.ele.tue.nl/pub/lp_solve/

=head1 AUTHOR

Wim Verhaegen E<lt>wim.verhaegen@ieee.orgE<gt>

=head1 COPYRIGHT

Copyright(c) 2000 Wim Verhaegen. All rights reserved. 
This program is free software; you can redistribute
and/or modify it under the same terms as Perl itself.

=cut
