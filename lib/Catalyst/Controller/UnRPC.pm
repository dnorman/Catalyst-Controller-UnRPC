package Catalyst::Controller::UnRPC;

use parent 'Catalyst::Controller';
use Scalar::Util 'blessed';

sub _process_errors {
    my ($self,$c) = @_;
    
    my @errors;
    while( my $error = shift @{ $c->error || [] } ){
        my $message;
	my $code    = 'general';
	
        if ( blessed $error ){
	    $code    = $error->code    if $error->can('code');
	    $message = $error->message if $error->can('message');
	    $message ||= $error;
	    
	}elsif(ref($error) eq 'SCALAR'){
	    $message = $error = $$error;
	}elsif(ref($error) eq 'ARRAY'){
            ($message)       = @$error if @error == 1;
            ($code,$message) = @$error if @error >= 2;
	}else{
	    $message = $error;
	}
	
        $c->log->error( $error );
        push @errors, { code => $code, message => $message };
    }
    
    return wantarray ? @errors : \@errors;
}

sub check_access { 1 }

1;