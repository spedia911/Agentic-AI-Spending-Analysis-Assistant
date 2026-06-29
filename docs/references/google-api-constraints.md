# Google API Constraints and Product Decisions

## Google Drive

Google Drive is the MVP ingestion source.

Why:

- The user can save financial screenshots into a dedicated folder.
- The Drive API supports listing files by folder, MIME type, and modified time.
- File IDs provide a stable basis for idempotent processing.
- The workflow is easier to demo and debug than broad photo-library scanning.

Useful implementation behavior:

- Filter to image MIME types.
- Store processed file IDs in `SourceDocuments`.
- Prefer file ID checkpoints over only using dates.
- Use modified time only as an optimization, not the only source of truth.

Reference:

- https://developers.google.com/workspace/drive/api/guides/search-files

## Google Sheets

Google Sheets is the MVP durable output and the backing data source for the individual web app.

Why:

- Easy for the user to inspect and correct.
- Easy for the web app to consume.
- Good fit for capstone demo visibility.
- Avoids premature database setup.

Useful implementation behavior:

- Use stable tab names.
- Write headers explicitly.
- Upsert by stable IDs to avoid duplicates.
- Keep source and audit tabs separate from summary tabs.

Reference:

- https://developers.google.com/workspace/sheets/api/guides/values

## Google Photos

Google Photos should be treated as an optional later source, not the primary MVP source.

Reason:

- Automatic full-library search is constrained by current Google Photos API behavior.
- A user-selected flow via Google Photos Picker is more realistic than assuming the app can scan all screenshots.
- The downstream data model should support a `photos` source type, but the first working ingestion path should be Drive.

Product decision:

- P0: Google Drive folder ingestion.
- P3: Google Photos user-selected ingestion, likely through Picker or an explicitly permitted source.

References:

- https://developers.google.com/photos/support/updates
- https://developers.google.com/photos/library/reference/rest/v1/mediaItems/search

