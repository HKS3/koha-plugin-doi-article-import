# Translation fragments

Koha uses separate catalogs for staff templates and Perl runtime messages.
These files follow that split:

- `*-staff-prog.po` contains Template Toolkit strings wrapped with `i18n.inc`.
- `*-messages.po` contains Perl strings wrapped with `Koha::I18N`.

English is the source language in the plugin. The `en-GB` files are identity
catalogs for language builds that require an explicit English catalog. The
`de-DE` files contain the German UI translation.

Merge the needed fragments into the corresponding Koha PO files and rebuild the
language files with Koha's standard translator tooling.
