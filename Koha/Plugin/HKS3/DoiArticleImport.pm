package Koha::Plugin::HKS3::DoiArticleImport;

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use CGI qw(-utf8);
use C4::Auth qw(haspermission);
use C4::Biblio qw(AddBiblio);
use C4::Context;
use HTML::Entities qw(decode_entities);
use JSON qw(decode_json encode_json);
use Koha::BiblioFrameworks;
use Koha::I18N qw(__ __x);
use LWP::UserAgent;
use MARC::Field;
use MARC::File::XML ( BinaryEncoding => 'UTF-8', RecordFormat => 'MARC21' );
use MARC::Record;
use POSIX qw(strftime);
use URI::Escape qw(uri_escape_utf8);

our $VERSION = '0.1.0';

our $metadata = {
    name            => 'DOI Article Import',
    author          => 'HKS3',
    description     => 'Import article metadata from Crossref DOI records into Koha MARC21',
    namespace       => 'doi_article_import',
    date_authored   => '2026-09-03',
    date_updated    => '2026-09-04',
    minimum_version => '23.11',
    maximum_version => undef,
    version         => $VERSION,
};

my $CONFIG_KEY = 'doi_article_import_config';
my $CROSSREF_PLUGIN_CLASS = 'Koha::Plugin::Com::PTFSEurope::Crossref';

sub new {
    my ( $class, $args ) = @_;

    my %localized_metadata = %{$metadata};
    $localized_metadata{name}        = __('DOI Article Import');
    $localized_metadata{description} = __('Import article metadata from Crossref DOI records into Koha MARC21');

    $args->{metadata}        = \%localized_metadata;
    $args->{metadata}{class} = $class;

    my $self = $class->SUPER::new($args);
    return unless $self;

    $self->{cgi} = $args->{cgi} || CGI->new;

    return $self;
}

sub tool {
    my ($self) = @_;

    my $cgi = $self->{cgi};
    my $op  = $cgi->param('op') || 'form';
    $op =~ s{\Acud-}{};

    my @errors;
    my @warnings;
    my %params = (
        doi           => scalar $cgi->param('doi') || q{},
        frameworkcode => defined $cgi->param('frameworkcode') ? scalar $cgi->param('frameworkcode') : $self->_config->{frameworkcode},
        itemtype      => defined $cgi->param('itemtype')      ? scalar $cgi->param('itemtype')      : $self->_config->{itemtype},
    );

    $params{itemtype} = 'AR' unless defined $params{itemtype} && $params{itemtype} ne q{};

    if ( $op eq 'preview' || $op eq 'create' ) {
        eval {
            my $doi      = normalize_doi( $params{doi} );
            my $work     = $self->fetch_crossref_work($doi);
            my $article  = crossref_work_to_article($work);
            my $record   = $self->build_article_record( $article, itemtype => $params{itemtype} );
            my $marcxml  = record_to_marcxml($record);
            my $dupes    = $self->find_existing_doi_biblios($doi);
            my $can_add  = $self->_current_user_can_create_biblio;
            my $created;

            push @warnings, @{ $article->{missing_required} || [] };

            if ( $op eq 'create' ) {
                if ( !$can_add ) {
                    die __("The logged-in user does not have the edit_catalogue permission.") . "\n";
                }
                if ( @{$dupes} && !$cgi->param('confirm_duplicate') ) {
                    push @errors,
                        __(
                        'A possible match for this DOI already exists in Koha. Please review it and create the record anyway if needed.'
                        );
                }
                else {
                    my ( $biblionumber ) = AddBiblio( $record, $params{frameworkcode} || q{} );
                    $created = $biblionumber;
                }
            }

            @params{qw(normalized_doi article marcxml duplicates can_create created_biblionumber)}
                = ( $doi, $article, $marcxml, $dupes, $can_add, $created );
        };

        if ($@) {
            my $error = $@;
            chomp $error;
            push @errors, $error;
        }
    }

    my $template = $self->get_template( { file => 'tool.tt' } );
    $template->param(
        plugin_class          => __PACKAGE__,
        errors                => \@errors,
        warnings              => \@warnings,
        frameworks            => $self->_frameworks,
        configured_email      => $self->_crossref_email || q{},
        has_configured_email  => $self->_crossref_email ? 1 : 0,
        confirm_duplicate     => scalar $cgi->param('confirm_duplicate') || 0,
        %params,
    );

    return $self->output_html( $template->output );
}

sub configure {
    my ($self) = @_;

    my $cgi = $self->{cgi};

    if ( $cgi->param('save') ) {
        my $config = {
            crossref_email_address => scalar $cgi->param('crossref_email_address') || q{},
            frameworkcode          => scalar $cgi->param('frameworkcode')          || q{},
            itemtype               => scalar $cgi->param('itemtype')               || 'AR',
        };

        $self->store_data( { $CONFIG_KEY => encode_json($config) } );
        return $self->go_home;
    }

    my $template = $self->get_template( { file => 'configure.tt' } );
    $template->param(
        plugin_class             => __PACKAGE__,
        config                   => $self->_config,
        crossref_plugin_email    => $self->_crossref_plugin_email || q{},
        frameworks               => $self->_frameworks,
    );

    return $self->output_html( $template->output );
}

sub intranet_js {
    my ( $self, $params ) = @_;

    my $page = $params->{page} || q{};
    return q{} unless $page =~ m{\A/cgi-bin/koha/cataloguing/(?:addbooks|cataloging-home)\.pl\z};

    my $payload = encode_json(
        {
            id    => 'doi-article-import-toolbar',
            url   => '/cgi-bin/koha/plugins/run.pl?class=' . uri_escape_utf8(__PACKAGE__) . '&method=tool',
            label => __('Import article by DOI'),
        }
    );

    return <<"JS";
<script>
(function () {
    const config = $payload;
    const toolbar = document.getElementById("toolbar");

    if (!toolbar || document.getElementById(config.id)) {
        return;
    }

    const buttonGroup = document.createElement("div");
    buttonGroup.className = "btn-group";
    buttonGroup.id = config.id;

    const link = document.createElement("a");
    link.className = "btn btn-default";
    link.href = config.url;

    const icon = document.createElement("i");
    icon.className = "fa fa-link";
    icon.setAttribute("aria-hidden", "true");

    link.appendChild(icon);
    link.appendChild(document.createTextNode(" " + config.label));
    buttonGroup.appendChild(link);
    toolbar.appendChild(buttonGroup);
})();
</script>
JS
}

sub install {
    return 1;
}

sub upgrade {
    return 1;
}

sub uninstall {
    return 1;
}

sub fetch_crossref_work {
    my ( $self, $doi ) = @_;

    $doi = normalize_doi($doi);
    die __("Please enter a DOI.") . "\n" if $doi eq q{};

    my $email = $self->_crossref_email;
    die __("Please configure a Crossref email address first.") . "\n"
        unless $email;

    my $ua = LWP::UserAgent->new(
        agent   => "Koha DOI Article Import/$VERSION (mailto:$email)",
        timeout => 20,
    );

    my $url = 'https://api.crossref.org/works/' . uri_escape_utf8($doi);
    $url .= '?mailto=' . uri_escape_utf8($email);

    my $response = $ua->get($url);
    if ( !$response->is_success ) {
        die __x( 'Crossref error: {status}', status => $response->status_line ) . "\n";
    }

    my $payload = eval { decode_json( $response->decoded_content ) };
    die __("The Crossref response could not be read as JSON.") . "\n" if $@ || !$payload;

    my $message = $payload->{message};
    die __("The Crossref response does not contain a work/message record.") . "\n"
        unless $message && ref $message eq 'HASH';

    return $message;
}

sub crossref_work_to_article {
    my ($work) = @_;

    my @authors = map { _author_from_crossref($_) } @{ $work->{author} || [] };
    @authors = grep { $_->{marc_name} ne q{} } @authors;

    my $year = _crossref_year(
        $work->{'published-print'},
        $work->{'published-online'},
        $work->{published},
        $work->{issued},
        $work->{created},
    );

    my $doi = normalize_doi( $work->{DOI} || q{} );
    my $article = {
        doi                 => $doi,
        doi_url             => $doi ? "https://doi.org/$doi" : q{},
        authors             => \@authors,
        author_statement    => join( '; ', map { $_->{display_name} } @authors ),
        title               => _first_array_value( $work->{title} ),
        subtitle            => join( ': ', _array_values( $work->{subtitle} ) ),
        year                => $year,
        journal_title       => _first_array_value( $work->{'container-title'} ),
        volume              => _plain_text( $work->{volume} ),
        issue               => _plain_text( $work->{issue} ),
        pages               => _plain_text( $work->{page} ),
        abstract            => _strip_markup( $work->{abstract} ),
        issn                => _first_array_value( $work->{ISSN} ),
        publisher           => _plain_text( $work->{publisher} ),
        language            => normalize_language( $work->{language} ),
        raw_type            => _plain_text( $work->{type} ),
    };
    $article->{enumeration} = build_host_enumeration($article);

    my @required = (
        [ authors       => __('Author names are missing in Crossref.') ],
        [ title         => __('Title is missing in Crossref.') ],
        [ year          => __('Publication year is missing in Crossref.') ],
        [ journal_title => __('Journal title is missing in Crossref.') ],
        [ volume        => __('Volume is missing in Crossref.') ],
        [ issue         => __('Issue is missing in Crossref.') ],
        [ pages         => __('Pages are missing in Crossref.') ],
        [ abstract      => __('Abstract is missing in Crossref.') ],
    );

    my @missing;
    for my $check (@required) {
        my ( $field, $message ) = @{$check};
        if ( $field eq 'authors' ) {
            push @missing, $message unless @{ $article->{authors} };
        }
        else {
            push @missing, $message unless defined $article->{$field} && $article->{$field} ne q{};
        }
    }
    $article->{missing_required} = \@missing;

    return $article;
}

sub build_article_record {
    my ( $self, $article, %opts ) = @_;

    my $record = MARC::Record->new;
    $record->leader('     naa a2200000   4500');

    $record->append_fields(
        MARC::Field->new( '005', _marc_005() ),
        MARC::Field->new( '008', _marc_008($article) ),
        MARC::Field->new( '040', ' ', ' ', a => 'DOI import' ),
    );

    if ( $article->{language} ) {
        _append_data_field( $record, '041', '0', ' ', a => $article->{language} );
    }

    if ( $article->{doi} ) {
        _append_data_field( $record, '024', '7', ' ', a => $article->{doi}, '2' => 'doi' );
        _append_data_field( $record, '856', '4', '0', u => $article->{doi_url}, y => 'DOI' ) if $article->{doi_url};
    }

    my @authors = @{ $article->{authors} || [] };
    if (@authors) {
        my $first = shift @authors;
        _append_data_field( $record, '100', '1', ' ', a => $first->{marc_name} );
        for my $author (@authors) {
            _append_data_field( $record, '700', '1', ' ', a => $author->{marc_name} );
        }
    }

    my @title_subfields;
    my $title = _plain_text( $article->{title} );
    my $subtitle = _plain_text( $article->{subtitle} );
    if ( $title ne q{} ) {
        $title = _append_suffix( $title, ' :' ) if $subtitle ne q{};
        push @title_subfields, a => $title;
    }
    if ( $subtitle ne q{} ) {
        $subtitle = _append_suffix( $subtitle, ' /' ) if $article->{author_statement};
        push @title_subfields, b => $subtitle;
    }
    push @title_subfields, c => $article->{author_statement} if $article->{author_statement};
    if (@title_subfields) {
        my $title_ind1 = @{ $article->{authors} || [] } ? '1' : '0';
        _append_data_field( $record, '245', $title_ind1, '0', @title_subfields );
    }

    _append_data_field( $record, '260', ' ', ' ', c => $article->{year} ) if $article->{year};

    if ( $article->{abstract} ) {
        _append_data_field( $record, '520', ' ', ' ', a => $article->{abstract} );
    }

    my @host;
    push @host, t => $article->{journal_title} if $article->{journal_title};
    push @host, g => $article->{enumeration} if $article->{enumeration};
    push @host, x => $article->{issn} if $article->{issn};
    _append_data_field( $record, '773', '0', ' ', @host ) if @host;

    _append_data_field( $record, '655', ' ', '4', a => 'Aufsatz' );

    my $itemtype = defined $opts{itemtype} ? $opts{itemtype} : $self->_config->{itemtype};
    $itemtype = 'AR' unless defined $itemtype && $itemtype ne q{};
    _append_data_field( $record, '942', ' ', ' ', '2' => 'z', c => $itemtype );

    return $record;
}

sub record_to_marcxml {
    my ($record) = @_;

    MARC::File::XML->default_record_format('MARC21');
    return MARC::File::XML::header('UTF-8')
        . MARC::File::XML::record($record)
        . MARC::File::XML::footer();
}

sub find_existing_doi_biblios {
    my ( $self, $doi ) = @_;

    $doi = normalize_doi($doi);
    return [] if $doi eq q{};

    my $doi_url = "https://doi.org/$doi";
    my $dbh = C4::Context->dbh;

    return $dbh->selectall_arrayref(
        q{
            SELECT b.biblionumber, b.title, b.author
            FROM biblio_metadata bm
            JOIN biblio b ON b.biblionumber = bm.biblionumber
            WHERE bm.metadata LIKE ?
               OR bm.metadata LIKE ?
            ORDER BY b.biblionumber
            LIMIT 20
        },
        { Slice => {} },
        '%' . $doi . '%',
        '%' . $doi_url . '%',
    );
}

sub build_host_enumeration {
    my ($article) = @_;

    my @parts;
    push @parts, 'Jg. ' . $article->{volume} if $article->{volume};
    push @parts, $article->{year}            if $article->{year};
    push @parts, 'Nr. ' . $article->{issue}  if $article->{issue};
    push @parts, 'S. ' . $article->{pages}   if $article->{pages};

    return join ', ', @parts;
}

sub normalize_doi {
    my ($doi) = @_;

    $doi = _plain_text( $doi // q{} );
    $doi =~ s{\A(?:https?://(?:dx\.)?doi\.org/|doi:\s*)}{}i;
    $doi =~ s{\A\s*DOI\s+}{}i;
    $doi =~ s{\s+}{}g;
    $doi =~ s{[).,;:]+\z}{};

    return lc $doi;
}

sub normalize_language {
    my ($value) = @_;

    $value = lc _plain_text( $value // q{} );
    my %map = (
        de  => 'ger',
        deu => 'ger',
        ger => 'ger',
        en  => 'eng',
        eng => 'eng',
        fr  => 'fre',
        fra => 'fre',
        fre => 'fre',
    );

    return $map{$value} || ( length($value) >= 3 ? substr( $value, 0, 3 ) : 'und' );
}

sub _current_user_can_create_biblio {
    my ($self) = @_;

    my $userenv = C4::Context->userenv || {};
    my $userid  = $userenv->{id};
    return 0 unless $userid;

    return haspermission( $userid, { editcatalogue => 'edit_catalogue' } ) ? 1 : 0;
}

sub _config {
    my ($self) = @_;

    my $stored = $self->retrieve_data($CONFIG_KEY) || '{}';
    my $config = eval { decode_json($stored) } || {};

    $config->{frameworkcode} //= q{};
    $config->{itemtype}      //= 'AR';

    return $config;
}

sub _crossref_email {
    my ($self) = @_;

    my $config_email = _plain_text( $self->_config->{crossref_email_address} || q{} );
    return $config_email if $config_email ne q{};

    my $plugin_email = _plain_text( $self->_crossref_plugin_email || q{} );
    return $plugin_email if $plugin_email ne q{};

    my $pref_email = _plain_text( C4::Context->preference('KohaAdminEmailAddress') || q{} );
    return q{} if $pref_email =~ /(?:localhost|example\.com)\z/i;

    return $pref_email;
}

sub _crossref_plugin_email {
    my ($self) = @_;

    my $json = eval {
        C4::Context->dbh->selectrow_array(
            q{
                SELECT plugin_value
                FROM plugin_data
                WHERE plugin_class = ?
                  AND plugin_key = 'crossref_config'
                LIMIT 1
            },
            undef,
            $CROSSREF_PLUGIN_CLASS,
        );
    };
    return q{} if $@ || !$json;

    my $config = eval { decode_json($json) } || {};
    return $config->{crossref_email_address} || q{};
}

sub _frameworks {
    my ($self) = @_;

    return [
        { frameworkcode => q{}, frameworktext => 'Default' },
        map {
            { frameworkcode => $_->frameworkcode, frameworktext => $_->frameworktext }
        } Koha::BiblioFrameworks->search( {}, { order_by => 'frameworktext' } )->as_list
    ];
}

sub _append_data_field {
    my ( $record, $tag, $ind1, $ind2, @subfields ) = @_;

    return unless defined $tag && defined $ind1 && defined $ind2;

    my @clean;
    while (@subfields) {
        my ( $code, $value ) = splice @subfields, 0, 2;
        next unless defined $value;
        $value = _plain_text($value);
        next if $value eq q{};
        push @clean, $code, $value;
    }
    return unless @clean;

    $record->append_fields( MARC::Field->new( $tag, $ind1, $ind2, @clean ) );
    return;
}

sub _crossref_year {
    for my $date (@_) {
        next unless $date && ref $date eq 'HASH';
        my $parts = $date->{'date-parts'};
        next unless $parts && ref $parts eq 'ARRAY' && ref $parts->[0] eq 'ARRAY';
        my $year = $parts->[0][0];
        return $year if defined $year && $year =~ /\A\d{4}\z/;
    }
    return q{};
}

sub _author_from_crossref {
    my ($author) = @_;

    return { marc_name => q{}, display_name => q{} } unless $author && ref $author eq 'HASH';

    my $family = _plain_text( $author->{family} || q{} );
    my $given  = _plain_text( $author->{given}  || q{} );
    my $name   = _plain_text( $author->{name}   || q{} );

    my $marc = $family && $given ? "$family, $given" : $family || $name || $given;
    my $display = $given && $family ? "$given $family" : $name || $marc;

    return {
        marc_name    => $marc,
        display_name => $display,
    };
}

sub _first_array_value {
    my ($value) = @_;
    my @values = _array_values($value);
    return @values ? $values[0] : q{};
}

sub _array_values {
    my ($value) = @_;

    return () unless defined $value;
    my @values = ref $value eq 'ARRAY' ? @{$value} : ($value);
    return grep { $_ ne q{} } map { _plain_text($_) } @values;
}

sub _strip_markup {
    my ($value) = @_;

    $value = _plain_text( $value // q{} );
    $value =~ s{<[^>]+>}{ }g;
    $value = decode_entities($value);
    $value =~ s{\s+}{ }g;
    $value =~ s{\A\s+|\s+\z}{}g;

    return $value;
}

sub _plain_text {
    my ($value) = @_;

    return q{} unless defined $value;
    $value = join ' ', @{$value} if ref $value eq 'ARRAY';
    return q{} if ref $value;
    $value =~ s{\r\n?}{\n}g;
    $value =~ s{\s+}{ }g;
    $value =~ s{\A\s+|\s+\z}{}g;

    return $value;
}

sub _append_suffix {
    my ( $value, $suffix ) = @_;

    $value = _plain_text($value);
    return $value if $value eq q{};
    return $value if $value =~ /\Q$suffix\E\z/;
    return $value if $value =~ /(?:[:;\/]\s*)\z/;

    return $value . $suffix;
}

sub _marc_005 {
    return strftime( '%Y%m%d%H%M%S.0', localtime );
}

sub _marc_008 {
    my ($article) = @_;

    my $entered = strftime( '%y%m%d', localtime );
    my $year    = $article->{year} && $article->{year} =~ /\A\d{4}\z/ ? $article->{year} : '    ';
    my $lang    = $article->{language} || 'und';
    my $value   = $entered . 's' . $year . '    ' . 'xx ' . '|||||||| |||| 00| 0 ' . $lang . ' d';

    return substr( $value . ( ' ' x 40 ), 0, 40 );
}

1;
