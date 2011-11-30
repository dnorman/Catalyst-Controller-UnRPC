package Catalyst::Controller::UnRPC::JsonStore;

use strict;
use warnings;
use Moose;
use Pod::JSchema;

BEGIN { extends 'Catalyst::Controller::UnRPC::JSON' };

use JSON;
has 'api' => (is => 'ro', lazy_build => 1 );

sub dispatch : Regex(.jsonstore$) {
    my (  $self, $c ) = @_;
    my $p = $c->stash->{params};
    
    $c->stash( mode => 'jsonstore' );
    
    my $path = '/' . $c->req->path; # or die \"No path specified";
    $path    =~ s/\.jsonstore$//i;
    
    my $xactionstr  = $p->{xaction} || 'read';
    my $xactions = $self->api->{ $path };
    my $def = $xactions->{$xactionstr} if $xactions;
    $c->stash( xactionstr => $xactionstr );
    
    my $action; 
    if( $def ){ # give the CRUD definitions the first right of refusal
	$action = $c->dispatcher->get_action_by_path($def->{path}) or die \"Invalid path '$path'";
    }else{
	if( $xactionstr eq 'read' ){ # look for an alternate action
	    $action = $c->dispatcher->get_action_by_path( $path );
	}
	unless ( $action && $action->attributes->{LIST} ){ # is the alternate action acceptable?
	    $xactions or die ["invalid", "Invalid path '$path'"]; # otherwise bail out
	    $def      or die ["invalid", "Invalid xaction '$xactionstr'"];
	}
    }
    
    $self->check_access( $c, $action );
    
    # HACK - this should be just sending a JSON post, but that doesn't work due to an ExtJS bug.
    if ( $c->req->params->{records} ){
        $p->{records} = JSON->new->allow_nonref->decode( $c->req->params->{records} );
    }
    
    
    $c->forward( $action , [ $p ] );
    
    my $response = $c->stash->{response} ||= {};
    ref( $response ) eq 'HASH' or die ["Sanity error - response not found"];
    
    my $root     = $c->stash->{root}  || 'records';
    my $data     = $response->{$root} ||= [];# || die ["Root '$root' not found"];
    
    $data = [$data] unless ref($data) eq 'ARRAY'; # data is always a list
    $response->{success} = JSON::true;
    if ( $xactionstr eq 'read' ){
        my $first = length (@$data) ? $data->[0] : {};
        
        my $fieldlist = $c->stash->{fields} || [ keys %{ $first } ];
        
        $response->{recordcount}   = scalar @{$data};
        $response->{metaData} = {
            idProperty      => $c->stash->{idProperty} || ( exists( $first->{idx} ) ? 'idx' : 'id'), # evil / lazy
            root            => $root,
            totalProperty   => 'recordcount',
            successProperty => 'success',
            messageProperty => 'message',
            fields          => $self->_metafields( $def, $fieldlist ),
        };
    }
    
}

sub _metafields{
    my ($self,$def,$fieldref) = @_;
    
    if ( ! exists $def->{snip} ){
        $def->{snip} = undef; # now exists but false
        my $schema = $def->{schema}           or return $fieldref;
        my $ret    = $schema->return_schema   or return $fieldref;
        
        my $snip = $ret->rawlocate('properties/records/items/properties') || $ret->rawlocate('properties/records/properties');
        
        ref($snip) eq 'HASH' or return $fieldref;
        $def->{snip} = $snip;
    }
    my $snip = $def->{snip} or return $fieldref;
    
    my @outfields;
    foreach my $name (@$fieldref){
        my $fdef = $snip->{$name};
        if(ref($fdef) eq 'HASH' and $fdef->{type}){
            push @outfields, { name => $name, type => $fdef->{type} };
        }else{
            push @outfields, { name => $name };
        }
    }
    
    return \@outfields;
}

sub end : Private {
    my( $self, $c ) = @_;
    return if $c->res->has_body;
    
    my @errors = $self->_process_errors( $c );
    
    my $response = $c->stash->{response} || {};
    if (@errors){
        # MUST SEND AS STATUS 200 IF ERROR
	my $main = $errors[0];
        $response = {
		     success => JSON::false,
		     message => $main->{message},
		     error_code => $main->{code},
		     (@errors > 1) ? (ERRORLIST => \@errors):()
	};
	if($c->stash->{xactionstr} eq 'read'){
	    $response->{metaData} = {
			    fields          => [],
			    successProperty => 'success',
			    messageProperty => 'message',
			};
	}
    }
    
    
    $c->res->content_type('application/json');
    $c->res->body( JSON::XS->new->convert_blessed->pretty->encode( $response ) );
}

sub _build_api {
    my ($self) = shift;
    my $c      = $self->_app;
    my %data;
    
    my %xaction_map = map {$_ => 1} qw'create read update destroy';

    foreach my $class ( $c->controllers ) {
        my $controller = $c->controller($class);
        
        my $ns = '/' . $controller->action_namespace;
        
        my $incmod = $controller->catalyst_component_name;
        $incmod =~ s/\:\:/\//g;
        $incmod .= '.pm';
        
        my %jschemas;
        if ( my $file = $INC{$incmod} ){
            my $pjs = Pod::JSchema->new( filename => $file );
            map { $jschemas{ $_->name } = $_->schema } @{ $pjs->methods || [] };
        }
        
        foreach my $method ( $controller->get_action_methods() ) {
            next unless ( my $action = $controller->action_for( $method->name ) );
            my $rpcstr  = $action->attributes->{RPC};
            next unless defined $rpcstr;
            $rpcstr = $rpcstr->[0] if ref($rpcstr) eq 'ARRAY';
            next unless defined $rpcstr;
            
            my @parts = map { lc ( $_ ) } split(/\W/, $rpcstr );
            foreach my $xaction ( grep { $xaction_map{$_} } @parts ){
                $data{$ns}{ $xaction } = { path => $action->private_path, schema => $jschemas{ $method->name } } ;
            }
        }
    }
    
    return \%data;
}

1;

=head2 end

Attempt to render a view, if needed.

1;
