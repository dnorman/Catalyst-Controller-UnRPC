package Catalyst::Controller::UnRPC::JSON;

use strict;
use warnings;
use parent 'Catalyst::Controller::UnRPC';
use JSON::XS;

sub begin : Private {
    my ($self, $c) = @_;
    
    my $ctype = $c->req->headers->header('content-type');
    #$c->log->debug("JSON request - Content-type: '$ctype'");
    
    my $json;
    my $p = $c->req->params;
    if ( defined($ctype) && $ctype =~ /application\/json/i){
        my $body = $c->req->body;
        $json = JSON::XS->new->allow_nonref->decode( <$body> );
    }elsif ($p->{jsonData}){
        $json = JSON::XS->new->allow_nonref->decode( delete $p->{jsonData} );
    }
    
    # $p must remain a hash
    if ( ref($json) eq 'HASH' ){
	$p = {  %$p, %$json };
	$c->stash( params => $p );
    }elsif( ref($json) eq 'ARRAY' ){
	$c->stash( params => $json ); # weird situation where $p and stash->{params} are divergent
    }else{
	$c->stash( params => $p );
    }
    
}

sub dispatch : Regex(.json$) {
    my (  $self, $c ) = @_;
    my $p = $c->stash->{params};
    
    my $path = '/' . $c->req->path;#     || die \"Invalid path";
    $path    =~ s/\.[^.]{1,10}//i;
    
    my $action = $c->dispatcher->get_action_by_path($path) or die ["notfound", "Invalid path '$path'"];
    
    $self->check_access( $c, $action );
    
    $c->forward( $action->private_path , [ $p ] );

}

sub end : Private {
    my( $self, $c ) = @_;
    
    my @errors = $self->_process_errors( $c );
    
    if (@errors){
	my $main = $errors[0];
        $c->response->status(400);
        $c->stash( response => {
		ERRORCODE => $main->{code},
		ERROR => $main->{message},
		(@errors > 1) ? (ERRORLIST => \@errors):()
	    }
	);
    }
    $c->stash->{response} ||= {};
    
    $c->forward( $c->view('JSON') );
}

1;
=head2 end

Attempt to render a view, if needed.

1;
