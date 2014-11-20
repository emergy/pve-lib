package pve;

use strict;
use warnings;

use LWP::UserAgent;
use Data::Dumper;
use JSON;
use HTTP::Cookies;

our $VERSION = 0.001;

=encoding utf8

=head1 NAME

pve - API for Proxmox virtualisation

=head1 SYNOPSIS

    use pve;

    $host = pve->new({
        host     => 'proxmox.domain',
        password => 'password',
        user     => 'root', # optional
        port     => 8006,   # optional
        realm    => 'pam',  # optional
    });

=cut

sub new {
    my ($class, $self) = @_;

    $self->{host}       || die "parameter 'host' is undef";
    $self->{password}   || die "parameter 'password' is undef";
    $self->{port}       ||= 8006;
    $self->{realm}      ||= 'pam';
    $self->{username}   ||= 'root';
    $self->{username} = $self->{username} . '@' . $self->{realm};

    my $ua = LWP::UserAgent->new;
    $ua->ssl_opts(verify_hostname => 0);

    my $response = $ua->post("https://$self->{host}:$self->{port}/api2/json/access/ticket", {
        username => $self->{username},
        password => $self->{password},
    });

    if ($response->is_success) {
        my $json = from_json($response->decoded_content);

        my $self = {
            username => $json->{data}->{username},
            ticket => $json->{data}->{ticket},
            CSRFPreventionToken => $json->{data}->{CSRFPreventionToken},
            host => $self->{host},
            port => $self->{port},
        };

        bless $self, $class;
        return $self;
    } else {
        die $response->status_line;
    }
}

=head2 get

Just takes a path as an argument and returns the value of action with the GET method

=cut

sub get {
    my $self = shift;
    action($self, 'GET', @_);
}

=head2 post

Takes two parameters: $path, \%post_data

=cut

sub post {
    my $self = shift;
    action($self, 'POST', @_);
}

sub action {
    my $self = shift;
    my ($method, $uri, $params) = @_;
    $uri =~ s{^/(?:api2/json)?/?(.*)}{$1};

    my $url = "https://$self->{host}:$self->{port}/api2/json/$uri";

    my $cookie_jar = HTTP::Cookies->new;
    $cookie_jar->set_cookie('', 'PVEAuthCookie', $self->{ticket}, '/', $self->{host});

    my $ua = LWP::UserAgent->new(cookie_jar => $cookie_jar);
    $ua->ssl_opts(verify_hostname => 0);

    my $response;
    if ($method eq 'POST') {
        $ua->add_handler(request_prepare => sub {
            my($request, $ua, $h) = @_;
            $request->header(CSRFPreventionToken => $self->{CSRFPreventionToken});
        });
    
        $response = $ua->post($url, $params);
    } elsif ($method eq 'GET') {
        $response = $ua->get($url);
    }
    
    if ($response->is_success) {
        my $json = from_json($response->decoded_content);
        return $json;
    } else {
        die $response->status_line;
    }
}

1;
