package t::MusicBrainz::Server::Controller::User::Edit;
use Test::Routine;
use Test::More;
use MusicBrainz::Server::Constants qw( :edit_status );
use MusicBrainz::Server::Test qw( html_ok test_xpath_html );

use HTTP::Status qw( :constants );

with 't::Mechanize', 't::Context';

test all => sub {

my $test = shift;
my $mech = $test->mech;
my $c    = $test->c;

MusicBrainz::Server::Test->prepare_test_database($c, '+editor');

$mech->get('/login');
$mech->submit_form( with_fields => { username => 'new_editor', password => 'password' } );

$mech->get_ok('/account/edit');
html_ok($mech->content);
$mech->submit_form( with_fields => {
    'profile.birth_date.year' => 0,
    'profile.birth_date.month' => 1,
    'profile.birth_date.day' => 1
} );
$mech->content_contains('invalid date', "Invalid date 0-1-1 triggers validation failure.");
$mech->submit_form( with_fields => {
    'profile.email' => 'new_email@example.com',
    'profile.birth_date.year' => '',
    'profile.birth_date.month' => '',
    'profile.birth_date.day' => ''
} );
$mech->content_contains('Your profile has been updated');
$mech->content_contains('We have sent you a verification email');

my $email_transport = MusicBrainz::Server::Email->get_test_transport;
my $email = $email_transport->shift_deliveries->{email};
is($email->get_header('To'), 'new_email@example.com', "Verification email sent to correct address");
is($email->get_header('Subject'), 'Please verify your email address', "Verification email has correct subject");

my $email_body = $email->object->body_str;
like($email_body, qr{http://localhost/verify-email.*}, "Verification email contains verification link");
like($email_body, qr{\[127\.0\.0\.1\]}, "Verification email contains request IP");

$email_body =~ qr{http://localhost(/verify-email.*)};
my $verify_email_path = $1;
$mech->get_ok($verify_email_path);
$mech->content_contains("Thank you, your email address has now been verified!");

$mech->get('/user/new_editor');
$mech->content_contains('new_email@example.com');


};

test 'Limited users cannot edit website and biography' => sub {
    my $test = shift;
    my $mech = $test->mech;
    my $c    = $test->c;

    MusicBrainz::Server::Test->prepare_test_database($c, '+editor');

    $mech->get('/login');
    $mech->submit_form( with_fields => { username => 'new_editor', password => 'password' } );

    $mech->get_ok('/account/edit');
    html_ok($mech->content);

    my $tx = test_xpath_html($mech->content);
    $tx->ok('//input[@id="id-profile.email"]', 'email field for all users');
    $tx->not_ok('//input[@id="id-profile.website"]', 'no website field for limited users');
    $tx->not_ok('//textarea[@id="id-profile.biography"]', 'no biography field for limited users');

    $test->c->sql->do(<<EOSQL);
INSERT INTO edit (id, editor, type, status, expire_time, autoedit) VALUES
    ( 1, 1, 1, $STATUS_APPLIED, now(), 0),
    ( 2, 1, 1, $STATUS_APPLIED, now(), 0),
    ( 3, 1, 1, $STATUS_APPLIED, now(), 0),
    ( 4, 1, 1, $STATUS_APPLIED, now(), 0),
    ( 5, 1, 1, $STATUS_APPLIED, now(), 0),
    ( 6, 1, 1, $STATUS_APPLIED, now(), 0),
    ( 7, 1, 1, $STATUS_APPLIED, now(), 0),
    ( 8, 1, 1, $STATUS_APPLIED, now(), 0),
    ( 9, 1, 1, $STATUS_APPLIED, now(), 0),
    (10, 1, 1, $STATUS_APPLIED, now(), 0);
EOSQL

    $mech->get_ok('/account/edit');
    html_ok($mech->content);

    $tx = test_xpath_html($mech->content);
    $tx->ok('//input[@id="id-profile.email"]', 'email field for all users');
    $tx->ok('//input[@id="id-profile.website"]', 'website field for normal (not imited) users');
    $tx->ok('//textarea[@id="id-profile.biography"]', 'biography field for normal (not limited) users');

    $mech->submit_form( with_fields => {
        'profile.website' => 'foo',
        'profile.biography' => 'hello world!',
    } );
    $mech->content_contains('Invalid URL format', "Invalid URL format 'foo' triggers validation failure.");
    $mech->submit_form( with_fields => {
        'profile.website' => 'http://example.com/~new_editor/',
        'profile.biography' => 'hello world!',
        'profile.email' => 'new_email@example.com',
    } );
    $mech->content_contains('Your profile has been updated');

    $mech->get('/user/new_editor');
    $mech->content_contains('http://example.com/~new_editor/');
    $mech->content_contains('hello world!');
};

test 'After removing email address, editors cannot edit' => sub {
    my $test = shift;
    my $mech = $test->mech;
    my $c    = $test->c;

    MusicBrainz::Server::Test->prepare_test_database($c, '+editor');
    $c->sql->do(
        'UPDATE editor SET email = ?, email_confirm_date = now()
         WHERE name = ?',
        'foo@bar.baz', 'new_editor'
    );

    $mech->get('/login');
    $mech->submit_form( with_fields => {
        username => 'new_editor',
        password => 'password'
    });

    {
        my $response = $mech->get('/artist/create');
        is($response->code, HTTP_OK);
    }

    $mech->get_ok('/account/edit');
    html_ok($mech->content);
    $mech->submit_form( with_fields => {
        'profile.email' => '',
    });
    $mech->content_contains('Your profile has been updated');

    {
        my $response = $mech->get('/artist/create');
        is($response->code, HTTP_UNAUTHORIZED);
    }
};

1;
