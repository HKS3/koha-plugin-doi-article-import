use Modern::Perl;

use Cwd qw(abs_path);
use FindBin qw($Bin);
use lib abs_path("$Bin/..");
use Test::More;

use C4::Biblio qw(AddBiblio DelBiblio);
use C4::Context;
use Koha::Plugin::HKS3::DoiArticleImport;

my $created_biblionumber;
END {
    if ($created_biblionumber) {
        eval { DelBiblio( $created_biblionumber, { skip_record_index => 1 } ) };
    }
}

my $article = {
    doi              => '10.9999/doi-article-import-test',
    doi_url          => 'https://doi.org/10.9999/doi-article-import-test',
    authors          => [ { marc_name => 'Testauthor, Tina', display_name => 'Tina Testauthor' } ],
    author_statement => 'Tina Testauthor',
    title            => 'DOI article import test',
    subtitle         => 'Roundtrip',
    year             => '2026',
    journal_title    => 'Test Journal',
    volume           => '12',
    issue            => '3',
    pages            => '44-55',
    abstract         => 'Roundtrip abstract',
    issn             => '1234-5678',
    language         => 'ger',
    enumeration      => 'Jg. 12, 2026, Nr. 3, S. 44-55',
};

my $plugin = bless {}, 'Koha::Plugin::HKS3::DoiArticleImport';
my $record = $plugin->build_article_record( $article, itemtype => 'AR' );

my ($biblionumber) = AddBiblio( $record, q{}, { skip_record_index => 1, disable_autolink => 1 } );
ok( $biblionumber, 'creates Koha biblio through AddBiblio' );

SKIP: {
    skip 'AddBiblio failed', 4 unless $biblionumber;
    $created_biblionumber = $biblionumber;

    my $dbh = C4::Context->dbh;
    my $metadata = $dbh->selectrow_hashref(
        'SELECT metadata FROM biblio_metadata WHERE biblionumber = ?',
        undef,
        $biblionumber,
    );
    ok( $metadata && $metadata->{metadata}, 'stores biblio_metadata' );
    like( $metadata->{metadata}, qr/10\.9999\/doi-article-import-test/, 'stores DOI in metadata' );
    like( $metadata->{metadata}, qr/Test Journal/, 'stores host journal in metadata' );

    my $error = DelBiblio( $created_biblionumber, { skip_record_index => 1 } );
    is( $error || q{}, q{}, 'deletes test biblio again' );
    $created_biblionumber = undef unless $error;
}

done_testing();
