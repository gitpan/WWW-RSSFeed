package WWW::RSSFeed;

use 5.008000;
use strict;
use warnings;
use threads qw(stringify);
use threads::shared;
use WWW::Mechanize;
use Domain::PublicSuffix;
use XML::RSS;
use HTML::Summary;
use HTML::TreeBuilder;
use HTML::Scrubber;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use WWW::RSSFeed ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
%feed_content_hr	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
getFeed
);

our $VERSION = '0.01';
our %feed_content_hr : shared;

=head1 NAME

WWW::RSSFeed - Perl extension for creating RSS feeds from website(s).

=head1 SYNOPSIS

    use WWW::RSSFeed;
    use strict;

    my %input = (
                 'url' => 'http://www.yahoo.com/', # required
                 'max_items' => 100, #optional
                 'min_description_word_limit'  => 50, #optional
                );

    my $feedObj = new WWW::RSSFeed(\%input);
    my $feedFile = $feedObj->getFeed();

=head1 DESCRIPTION

RSSFeed module can be used to create RSS feeds from website(s). This
module is provided as it is, the user is responsible if this module is used
to aggresively spider websites other than that of owner's. This activity may cause legal
obligations, so the user is hereby made aware. Use this on your own website.

=head2 METHODS

    new() - The new subroutine.
    getFeed() - Returns feed as a scalar.
    __get_url_contents() - Returns global hash with title, link, description, links to other pages 
                       in same domain and serial number. Increments global item count and
                       adds links to global hash.

=head1 SEE ALSO

This module is used at http://www.feedify.me/ ; a not for profit service from author 
for webmasters.

=head1 AUTHOR

Kunal Jaiswal <kunal.jaiswal@yahoo.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by Kunal Jaiswal

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.12.4 or,
at your option, any later version of Perl 5 you may have available.

=cut

######################################################################
######################################################################
#######                                                      #########
#######    new subroutine to define basic information.       #########
#######                                                      #########
######################################################################
######################################################################

sub new{

    my ( $pkg, $input ) = @_;
    my $obj = $input;
    @_=();

    ## Set optional parameter if not supplied.
    if(!$obj->{'max_items'}){
        $obj->{'max_items'} = 20;
    }

    if(!$obj->{'min_description_word_limit'}){
        $obj->{'min_description_word_limit'} = 50;
    }

    $feed_content_hr{'counter'} = 1;

    bless( $obj, ref($pkg) || $pkg );
    
    return $obj;
}


######################################################################
######################################################################
#######                                                      #########
#######    Returns feed filename or feed as a scalar.        #########
#######                                                      #########
######################################################################
######################################################################

sub getFeed{

    my ( $self ) = @_;
    @_=();
    
    threads->create(\&__get_url_contents, $self)->join();
    
    return $self->__create_rss();
}

######################################################################
######################################################################
#######                                                      #########
#######   Returns global hash with title, link, description, #########
#######   links to other pages in same domain and serial     #########
#######   number. Increments global item count and adds      #########
#######   links to global hash. Only to be called with       #########
#######   threads.                                           #########
#######                                                      #########
######################################################################
######################################################################

sub __get_url_contents{

    my $self;

    ($self) = @_ if(@_);

    undef @_;

    if($feed_content_hr{$self->{'url'}}){ return ; }

    my $mech = WWW::Mechanize->new( timeout => 0.99 );
    $mech->get($self->{'url'});

    my $tree = new HTML::TreeBuilder;
    my $html_content = $mech->content();

    my $scrubber = HTML::Scrubber->new;

    $scrubber->default(1);
    $scrubber->deny(qw[script style]);

    $html_content = $scrubber->scrub($html_content);

    $tree->parse( $html_content );
    my $summarizer = new HTML::Summary(
        LENGTH =>  1500,
        USE_META => 1,
    );

    my $summary = $summarizer->generate($tree);

    $feed_content_hr{$self->{'url'}} = &share({});
    $feed_content_hr{$self->{'url'}}{'title'} = $mech->title();
    $feed_content_hr{$self->{'url'}}{'description'} = $summary;

    my $unwanted_files = 'css|js|jpg|jpeg|png|bmp|gif|tif|tiff|svg';
    my @links = $mech->find_all_links( tag_regex => qr/^a$/,
                                       url_regex => qr/[^$unwanted_files]$/); 

    my $suffix = new Domain::PublicSuffix ({});

    @links = $self->__get_valid_links($suffix->get_root_domain($self->__root_domain($self->{'url'})), $suffix, @links);

    foreach my $link(@links){
       if (($feed_content_hr{'counter'} < $self->{'max_items'}) && ($link)){
           $self->{'url'} = $link;
	   $feed_content_hr{'counter'}++;
           my $thread = threads->new(\&__get_url_contents, $self);
           $thread->join();
       }
    }
}

######################################################################
######################################################################
#######                                                      #########
#######    Gives the root domain from a given url.           #########
#######                                                      #########
######################################################################
######################################################################

sub __root_domain{

    my ( $self, $url ) = @_;
    @_=();
    $url =~ /([^:]*:\/\/)?([^\/]+)/g;
    return $2; 

}


######################################################################
######################################################################
#######                                                      #########
#######    Gives the root domain from a given url.           #########
#######                                                      #########
######################################################################
######################################################################

sub __get_valid_links{

    my ( $self, $url, $suffix, @links ) = @_;
    @_=();

    @links = map { $_ = $self->__get_inbound_links($url, $suffix, $_->url()); } @links; 

    ##Send unique links
    @links = keys %{{ map { $_ => 1 } @links }};
    return @links;
}

######################################################################
######################################################################
#######                                                      #########
#######    Gives the root domain from a given url.           #########
#######                                                      #########
######################################################################
######################################################################

sub __get_inbound_links{
    
    my ($self, $url, $suffix, $current_link) = @_;
    @_=();

    if(($current_link =~ /^http/) 
      && ($suffix->get_root_domain($self->__root_domain($current_link)) ne $url)){
	return '';
    }

    if($current_link =~ /$url/){ return $current_link; }

    if($current_link !~ /^mailto:|javascript|\#/g){

        if($current_link !~ /^\//){ $current_link = '/'.$current_link; }
        $current_link = "http://".$url.$current_link;    

    }else{
        $current_link = '';
    }

    return $current_link;

}

######################################################################
######################################################################
#######                                                      #########
#######    Gives the root domain from a given url.           #########
#######                                                      #########
######################################################################
######################################################################

sub __create_rss{

    my ($self) = @_;
    @_=();
    
    my $rss = XML::RSS->new (version => '2.0');

    foreach my $url(keys %feed_content_hr){

        if($url ne 'counter'){
            $rss->add_item(title => $feed_content_hr{$url}{'title'},
                           link  => $url,
                           description => $feed_content_hr{$url}{'description'});
        }
    }


    return $rss->as_string;
}

1;
__END__









