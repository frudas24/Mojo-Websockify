use Mojolicious::Lite;

use Mojo::IOLoop;

websocket '/proxy' => sub {
  my $c = shift;
  $c->render_later->on(finish => sub { warn 'websocket closing' });

  my $tx = $c->tx;
  $tx->with_protocols('binary');

  my $host = $c->param('target') || '127.0.0.1';
  my $port = $host =~ s/:(\d+)$// ? $1 : 5901;

  Mojo::IOLoop->client(address => $host, port => $port, sub {
    my ($loop, $err, $tcp) = @_;

    $tx->finish(4500, "TCP connection error: $err") if $err;
    $tcp->on(error => sub { $tx->finish(4500, "TCP error: $_[1]") });

    $tcp->on(read => sub {
      my ($tcp, $bytes) = @_;
      $tx->send({binary => $bytes});
    });

    $tx->on(binary => sub {
      my ($tx, $bytes) = @_;
      $tcp->write($bytes);
    });

    $tx->on(finish => sub {
      $tcp->close;
      undef $tcp;
      undef $tx;
    });
  });
};

get '/*target' => sub {
  my $c = shift;
  my $target = $c->stash('target');
  my $url = $c->url_for('proxy')->query(target => $target);
  $url->path->leading_slash(0); # novnc assumes no leading slash :(
  $c->render(
    vnc  =>
    base => $c->tx->req->url->to_abs,
    path => $url,
  );
};

app->start;

