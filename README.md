# DOI Article Import

Koha plugin for Work Item 16. It provides a staff tool that loads article
metadata from Crossref by DOI, shows a preview, renders MARCXML and can create a
Koha bibliographic record.

The plugin is intentionally independent from `koha-plugin-api-crossref`. If that
plugin is installed and configured, this plugin reuses its
`crossref_email_address` as a fallback. A dedicated email address can also be
stored in this plugin's own configuration.

## Mapping

| Crossref value | MARC21 |
| --- | --- |
| DOI | `024 7_ $a 10... $2 doi`, `856 40 $u https://doi.org/... $y DOI` |
| first author | `100 1_ $a` |
| further authors | `700 1_ $a` |
| article title | `245 10 $a` |
| subtitle | `245 10 $b` |
| author statement | `245 10 $c` |
| publication year | `260 __ $c` |
| journal title | `773 0_ $t` |
| volume/year/issue/pages | `773 0_ $g` |
| ISSN | `773 0_ $x` |
| abstract | `520 __ $a` |
| article genre | `655 _4 $a Aufsatz` |
| item type | `942 __ $2 z $c AR` by default |

The plugin creates bibliographic records only. It does not create item records.

## Permissions

Staff users need the Koha plugin permission `plugins => tool` to open the tool.
Creating records also requires `editcatalogue => edit_catalogue`.

## Koha master compatibility

POST forms use Koha's `cud-*` operation naming and include `csrf-token.inc`.
Template strings are wrapped with Koha's `i18n.inc` macros and Perl messages use
`Koha::I18N`, so the plugin strings can be extracted for translation.
The cataloging toolbar link is injected through the plugin `intranet_js` hook on
`cataloguing/cataloging-home.pl` and `cataloguing/addbooks.pl`; it does not
require any Koha core template change.

English is the source language for user-facing strings, matching Koha's normal
translation workflow. Translation fragments are shipped in `po/`:

- `*-staff-prog.po` for Template Toolkit strings from the staff interface
- `*-messages.po` for Perl strings translated through `Koha::I18N`

For installation into a translated Koha instance, merge these fragments into the
matching Koha PO files and rebuild the language files with Koha's normal
translator tooling.

## Build

```sh
scripts/build-kpz
```

The package is written to `dist/koha-plugin-doi-article-import-vVERSION.kpz`.

## KTD test

Copy the `Koha` directory into the KTD instance's plugin directory and run
Koha's plugin installer:

```sh
docker cp Koha nm2dbmaster-koha-1:/var/lib/koha/kohadev/plugins/
docker exec nm2dbmaster-koha-1 koha-shell -c \
  "perl /usr/share/koha/bin/devel/install_plugins.pl --include Koha::Plugin::HKS3::DoiArticleImport" kohadev
```

The staff tool is available under plugins as `DOI Article Import`.
