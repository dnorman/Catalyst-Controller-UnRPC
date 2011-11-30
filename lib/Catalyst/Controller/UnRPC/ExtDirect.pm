package Catalyst::Controller::UnRPC::ExtDirect;

use strict;
use warnings;
use Moose;
use JSON::XS;

BEGIN { extends 'Catalyst::Controller::UnRPC::JSON' };

has 'api'    => ( is => 'rw', lazy_build => 1 );
has 'routes' => ( is => 'rw' );

sub src : Local {
    my ($self, $c) = @_;
    my $p = $c->req->params;
    
    my $basepath = $p->{basepath};
    my $url = $c->dispatcher->uri_for_action( $self->action_for('dispatch') ) ->as_string;
    $url = "$basepath$url" if $basepath =~ /^\/\w+$/;
    
    my $api = {
        url     => $url, 
        type    => 'remoting',
        actions => $self->api
    };
    
    my $namespace = $c->req->params->{namespace};
    $api->{namespace} = $namespace if $namespace && $namespace =~ /^\w+(\.\w+)?$/;
    
    my $var = $p->{var} || 'Ext.app.REMOTING_API';
    $var =~ /^[\w\.]+$/ or die ["Invalid var parameter"];
    
    $c->res->content_type('application/javascript');
    $c->res->body( "$var = " . JSON::XS::encode_json( $api ) . ';' );
}

sub _build_api {
    my ($self) = @_;
    my $c      = $self->_app;
    my $data   = {};
    
    foreach my $name ( $c->controllers ) {
        my $controller = $c->controller( $name );
        $name =~ s/:://g;
        
        my @methods;
        foreach my $method ( $controller->get_action_methods() ) {
            
            next unless my $action = $controller->action_for( $method->name );
            next unless ( exists $action->attributes->{RPC} );
            
            push @methods, { len => 1, name => $method->name };
            $self->{routes}{ $name }{ $method->name } = { len => 1, path => $action->private_path };

        }
        if (@methods){
            $data->{ $name } = \@methods;
        }
    }
    
    return $data;
}

sub dispatch : Local {
    my ($self, $c) = @_;
    
    $self->api;
    my $routes = $self->routes;
    
    my $reqs = delete $c->stash->{params} or die ['No params found'];
    $reqs = [ $reqs ] unless ref $reqs eq 'ARRAY';
    
    my @out;
    foreach my $req (@$reqs) {
        
        $req                  or die ['Missing instruction'];
        length $req->{action} or die ["Missing action"];
        
        $routes->{ $req->{action} } or die ["Invalid action '$req->{action}'"];
        my $route = $routes->{ $req->{action} }->{ $req->{method} } or die ["Invalid method '$req->{method}'"];
        
        my $path = $route->{path};
        my $action = $c->dispatcher->get_action_by_path( $path ) or die ["notfound", "Invalid path '$path'"];
        
        $self->check_access( $c, $action );
        
        my $data = $req->{data};
        $data = [$data] unless ref ($data) eq 'ARRAY';

        my $stash = local $c->{stash} = { %{ $c->{stash} } };
        my $error = local $c->{error} = undef;
        
        $c->forward( $path , $data );
        
        my @errors = $self->_process_errors( $c );
        
        if(@errors){
            my $main = $errors[0]; 
            push @out, {
                        type => 'exception',
                        tid  => $req->{tid},
                        message    => $main->{message},
                        error_code => $main->{code},
                        (@errors > 1) ? ( error_list => \@errors ):()
                    }
        }else{
            push @out, {
                        ( map { $_ => $req->{$_} } qw'action method tid type' ),
                        result => $stash->{response},
                    };

        }
    }
    
    $c->stash( response => @out == 1 ? $out[0] : \@out );

}

sub end : Private {
    my( $self, $c ) = @_;
    return if $c->res->has_body;
    
    my @errors = $self->_process_errors( $c );
    
    my $response = $c->stash->{response} || {};
    if (@errors){
        $c->response->status(400);
	my $main = $errors[0];
        $response = { type => 'exception', message => $main->{message}, error_code => $main->{code}, (@errors > 1) ? (ERRORLIST => \@errors):() };
    }
    
    $c->res->content_type('application/json');
    $c->res->body( JSON::XS->new->convert_blessed->pretty->encode( $response ) );
}

1;