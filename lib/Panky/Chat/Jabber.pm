package Panky::Chat::Jabber;
use AnyEvent::XMPP::IM::Connection;
use AnyEvent::XMPP::Ext::Disco;
use AnyEvent::XMPP::Ext::MUC;
use Mojo::Base 'Panky::Chat';

# ABSTRACT: Jabber Chat Agent for Panky

has [ qw( host jid password room muc jc resource ) ];

has required_env => sub{[qw(
    PANKY_CHAT_JABBER_JID PANKY_CHAT_JABBER_PWD PANKY_CHAT_JABBER_ROOM
)]};

sub setup {
    my ($self) = @_;

    # Set up everything that isn't already setup (i.e was not passed in)
    $self->jid( $self->jid // $ENV{PANKY_CHAT_JABBER_JID} );
    $self->password( $self->password // $ENV{PANKY_CHAT_JABBER_PWD} );
    $self->room( $self->room // $ENV{PANKY_CHAT_JABBER_ROOM} );
    $self->host( $self->host // $ENV{PANKY_CHAT_JABBER_HOST} );
    $self->resource(
        $self->resource // $ENV{PANKY_CHAT_JABBER_RESOURCE} // 'panky'
    );
}

sub connect {
    my ($self) = @_;

    # Parse user/domain from jid
    my ($username, $domain) = split /@/, $self->jid;

    # Set the nick to the first fart of the JID
    $self->nick( $username );

    # Create the connection object
    my $jc = AnyEvent::XMPP::IM::Connection->new(
        username => $username,
        domain => $domain,
        password => $self->password,
        host => $self->host,
        resource => $self->resource,
    );

    # Save the jabber connection to oursef
    $self->jc( $jc );

    # Add MUC Extension
    $jc->add_extension (my $d = AnyEvent::XMPP::Ext::Disco->new);
    $jc->add_extension(my $muc = AnyEvent::XMPP::Ext::MUC->new( disco => $d ));

    # Save the muc object to ourself
    $self->muc( $muc );

    # Join the room once we're connected
    $jc->reg_cb (stream_ready => sub {
        $muc->join_room($jc, $self->room, $self->nick)
    });

    # Handle messages
    $muc->reg_cb( message => sub { $self->_dispatch( @_ ) });

    # Reconnect on disconnect
    $jc->reg_cb (disconnect => sub { $jc->connect });

    # Connect to jabber
    $jc->connect;

    # Store objects that we'll want to self
    $self->attr('_jc' => sub { $jc });
    $self->attr('_muc' => sub { $muc });

    # Return $self so we are chainable
    return $self;
}

# Tells the chat agent to say something in the chat room
# msg - the body of the message to send to the room
# to_nick - (optional) the user to say the msg to ("$to_nick: $msg")
sub say {
    my ($self, $msg, $to_nick) = @_;

    # Prepend $to_nick to message if given
    $msg = "$to_nick: $msg" if $to_nick;

    # Send the msg
    my $m = $self->muc->get_room( $self->jc, $self->room )->make_message(
        body => $msg
    )->send;
}

# Dispatches messages received in the chatroom to their appropriate
# listeners based on the type of the message.
sub _dispatch {
    my ($self, $muc, $room, $msg, $is_echo) = @_;

    # We don't care about echo's or delayed messages
    return if $is_echo || $msg->is_delayed;

    my $nick = $self->nick;
    # directed_message if it's directed to us, otherwise it's
    # just regular chatter in the chatroom.
    my $type = $msg->body ~~ /^$nick\W/ ? 'directed_message' : 'message';

    # Call the dispatcher
    $self->dispatch( $type, $msg->body, $msg->from_nick );
}

1;

=head1 SYNOPSIS

L<Panky::Chat::Jabber> provides C<Jabber> chat support for the L<Panky> chat
bot.

=head1 Environment Variables

The following Environment Variables are required for this module to work:

=over

=item B<PANKY_CHAT_JABBER_JID>

The C<jid> of the L<Panky> jabber chat account.

=item B<PANKY_CHAT_JABBER_PWD>

The password of the L<Panky> jabber chat account.

=item B<PANKY_CHAT_JABBER_ROOM>

The C<jid> of the jabber chat room for L<Panky> to join
C<(room@conference.jabber.server.com)>

=back

And the following Environment Variables are optional:

=over

=item B<PANKY_CHAT_JABBER_HOST>

This allows you to optionally set a host for the jabber connectino if it is
different from the C<domain> in the C<jid (user@domain.tld)>.

=back
