use Modern::Perl;

use Cwd qw(abs_path);
use FindBin qw($Bin);
use lib abs_path("$Bin/..");
use Test::More;

use Koha::Plugin::HKS3::DoiArticleImport;

my $plugin = Koha::Plugin::HKS3::DoiArticleImport->new( { enable_plugins => 1 } );
ok( $plugin, 'creates plugin object' );

my $frameworks = [ { frameworkcode => q{}, frameworktext => 'Default' } ];

my $tool = $plugin->get_template( { file => 'tool.tt' } );
$tool->param(
    plugin_class         => 'Koha::Plugin::HKS3::DoiArticleImport',
    errors               => [],
    warnings             => [],
    frameworks           => $frameworks,
    configured_email     => 'catalog@example.org',
    has_configured_email => 1,
    confirm_duplicate    => 0,
    doi                  => q{},
    frameworkcode        => q{},
    itemtype             => 'AR',
    article              => {
        doi           => '10.9999/template-test',
        authors       => [],
        title         => 'Template test',
        subtitle      => q{},
        year          => '2026',
        journal_title => 'Test journal',
        volume        => '1',
        issue         => '1',
        pages         => '1-2',
        abstract      => q{},
        issn          => q{},
    },
    marcxml              => '<record />',
    duplicates           => [],
    can_create           => 1,
    created_biblionumber => undef,
);
my $tool_output = $tool->output;
like( $tool_output, qr/DOI Article Import/, 'renders tool template' );
like( $tool_output, qr/name="csrf_token"/, 'tool forms include CSRF token' );
like( $tool_output, qr/name="op" value="cud-preview"/, 'preview form uses CUD op' );
like( $tool_output, qr/name="op" value="cud-create"/, 'create form uses CUD op' );

my $configure = $plugin->get_template( { file => 'configure.tt' } );
$configure->param(
    plugin_class          => 'Koha::Plugin::HKS3::DoiArticleImport',
    config                => { crossref_email_address => q{}, frameworkcode => q{}, itemtype => 'AR' },
    crossref_plugin_email => q{},
    frameworks            => $frameworks,
);
my $configure_output = $configure->output;
like( $configure_output, qr/Configure DOI Article Import/, 'renders configure template' );
like( $configure_output, qr/name="csrf_token"/, 'configure form includes CSRF token' );
like( $configure_output, qr/name="op" value="cud-save"/, 'configure form uses CUD op' );

is(
    $plugin->intranet_js( { page => '/cgi-bin/koha/mainpage.pl' } ),
    q{},
    'does not inject toolbar link outside cataloging'
);

for my $page (qw(/cgi-bin/koha/cataloguing/cataloging-home.pl /cgi-bin/koha/cataloguing/addbooks.pl)) {
    my $js = $plugin->intranet_js( { page => $page } );
    like( $js, qr/doi-article-import-toolbar/, "injects toolbar link on $page" );
    like( $js, qr/Import article by DOI/, "toolbar link label is present on $page" );
    like(
        $js,
        qr{/cgi-bin/koha/plugins/run\.pl\?class=Koha%3A%3APlugin%3A%3AHKS3%3A%3ADoiArticleImport&method=tool},
        "toolbar link target is the plugin tool on $page"
    );
}

done_testing();
