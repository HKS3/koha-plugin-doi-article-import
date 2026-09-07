use Modern::Perl;

use Cwd qw(abs_path);
use FindBin qw($Bin);
use lib abs_path("$Bin/..");
use Test::More;

use_ok('Koha::Plugin::HKS3::DoiArticleImport');

my $work = {
    DOI    => 'https://doi.org/10.37307/J.2363-9768.2026.02.03',
    author => [
        { given => 'Uwe',  family => 'Hennig' },
        { given => 'Anna', family => 'Beispiel' },
    ],
    title              => ['Aktuelles'],
    subtitle           => ['Untertitel'],
    issued             => { 'date-parts' => [ [2026, 2, 1] ] },
    'container-title'  => ['Die Rentenversicherung'],
    volume             => '81',
    issue              => '2',
    page               => '101-108',
    abstract           => '<jats:p>Abstract text &amp; details.</jats:p>',
    ISSN               => ['2363-9768'],
    language           => 'de',
    type               => 'journal-article',
};

my $article = Koha::Plugin::HKS3::DoiArticleImport::crossref_work_to_article($work);
is( $article->{doi}, '10.37307/j.2363-9768.2026.02.03', 'normalizes DOI' );
is( $article->{doi_url}, 'https://doi.org/10.37307/j.2363-9768.2026.02.03', 'builds DOI URL' );
is_deeply( $article->{missing_required}, [], 'sample contains all required issue fields' );

my $plugin = bless {}, 'Koha::Plugin::HKS3::DoiArticleImport';
my $record = $plugin->build_article_record( $article, itemtype => 'AR' );

is( $record->field('041')->subfield('a'), 'ger', 'maps language' );
is( $record->field('024')->subfield('a'), '10.37307/j.2363-9768.2026.02.03', 'maps DOI identifier' );
is( $record->field('024')->subfield('2'), 'doi', 'marks DOI identifier source' );
is( $record->field('856')->subfield('u'), 'https://doi.org/10.37307/j.2363-9768.2026.02.03', 'maps DOI URL' );
is( $record->field('100')->subfield('a'), 'Hennig, Uwe', 'maps first author' );
is( $record->field('700')->subfield('a'), 'Beispiel, Anna', 'maps further author' );
is( $record->field('245')->indicator(1), '1', 'sets title main-entry indicator when author exists' );
is( $record->field('245')->subfield('a'), 'Aktuelles :', 'maps title' );
is( $record->field('245')->subfield('b'), 'Untertitel /', 'maps subtitle' );
is( $record->field('245')->subfield('c'), 'Uwe Hennig; Anna Beispiel', 'maps statement of responsibility' );
is( $record->field('260')->subfield('c'), '2026', 'maps publication year' );
is( $record->field('520')->subfield('a'), 'Abstract text & details.', 'maps and cleans abstract' );
is( $record->field('773')->subfield('t'), 'Die Rentenversicherung', 'maps journal title' );
is( $record->field('773')->subfield('g'), 'Jg. 81, 2026, Nr. 2, S. 101-108', 'maps host enumeration' );
is( $record->field('773')->subfield('x'), '2363-9768', 'maps ISSN' );
is( $record->field('655')->subfield('a'), 'Aufsatz', 'marks article genre' );
is( $record->field('942')->subfield('c'), 'AR', 'maps configured item type' );

my $marcxml = Koha::Plugin::HKS3::DoiArticleImport::record_to_marcxml($record);
like( $marcxml, qr/<datafield tag="773"/, 'renders MARCXML with host field' );
like( $marcxml, qr/<datafield tag="520"/, 'renders MARCXML with abstract field' );

done_testing();
