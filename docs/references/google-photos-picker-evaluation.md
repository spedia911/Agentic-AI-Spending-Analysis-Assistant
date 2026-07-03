# Google Photos Picker Evaluation

Last reviewed: 2026-07-02

## Decision

Keep Google Drive as the submitted MVP ingestion source. Treat Google Photos as an optional future extension using the Google Photos Picker API, not automatic full-library scanning.

## Current API Findings

Official Google Photos documentation describes the Picker API as the secure way for users to select photos and videos from their Google Photos library and share them with an app:

- https://developers.google.com/photos/picker/guides/get-started-picker

The Picker API flow is user-selected:

1. Check for an OAuth token.
2. Create a picker session.
3. Send the user to the returned picker URI.
4. Poll the session until selected media is ready.
5. List selected media items.
6. Fetch selected media content from each item's `baseUrl`.

Google's Photos API update notes explain why this project should not assume broad library scanning. As of the 2025 changes, user-library selection should move to Picker API, while Library API access is refocused toward app-created content:

- https://developers.google.com/photos/support/updates

## Fit For This Product

Picker API fits a later "choose screenshots from Photos" workflow:

- The user explicitly selects financial screenshots.
- Selected media item IDs can map to `SourceDocuments.source_document_id`.
- `SourceDocuments.source_type` already supports `photos`.
- Downstream extraction, normalization, validation, categorization, review, Sheets writing, anomaly detection, and dashboard display do not need a separate data model.

Picker API does not replace the Drive-first MVP because:

- The current product decision is Drive-first until the stable ingestion workflow is complete.
- The submitted demo needs a low-friction folder-based source that a reviewer can populate without building a full OAuth picker flow.
- Automatic full-library screenshot search is not an appropriate current Photos API assumption.

## Future Implementation Shape

When implemented, add a `photos` ingestion adapter that:

1. Starts a Picker API session for the configured single user.
2. Stores selected media item IDs as stable `SourceDocuments.source_document_id` values.
3. Stores `source_type = photos`.
4. Stores the selection or media creation timestamp in existing source timestamp fields where available.
5. Downloads selected media bytes into the same private cache used by Drive screenshots.
6. Reuses the existing processing pipeline unchanged.

## MVP Status

No code is required for submitted MVP readiness beyond preserving the `photos` source type and documenting this decision. Drive remains the stable default and Photos remains an optional extension.
