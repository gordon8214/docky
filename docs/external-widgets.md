# Legacy community widgets

This AppKit fork supports built-in widgets only. It does not discover or execute
community widget code, offer a Widget Store, download bundles, or handle widget
installation links. Existing `.dockywidget` bundles are left on disk.

Saved `external:<identifier>` values still decode. Placements, spans, per-widget
settings, profiles, and Smart Stack visibility settings retain their existing
formats. These widgets render an “Unsupported community widget” placeholder and
can be removed through the usual tile or Smart Stack context menu. Saved external placements supply Smart Stack placeholders using their original
owner identifiers. Bundle identifiers are not treated as widget identifiers, and
installed bundles do not introduce new Smart Stack entries. The app never loads
their executable code.
