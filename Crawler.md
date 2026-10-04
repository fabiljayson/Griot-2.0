# Griot AI — Cultural Heritage Crawler Integration

I want you to modify my existing crawler so that it can automatically discover, extract, normalize, validate, and import relevant **Cameroonian cultural heritage information** into my Griot AI project.

The purpose of this crawler is to populate the Griot AI database with reliable cultural heritage information that can later be reviewed and validated by administrators.

## 1. Target Sources

Add the following websites as configured crawler sources:

### Primary / authoritative sources

- Cameroon National Museum:
  https://cameroon-nationalmuseum.cm/

- Musécam — Musée National du Cameroun:
  https://www.musecam.org/

- Ministry of Arts and Culture of Cameroon (MINAC):
  https://minac.gov.cm/

- MINAC cultural heritage resources:
  https://www.minac-gouv.com/patrimoine-culturel/

- UNESCO Intangible Cultural Heritage — Cameroon:
  https://ich.unesco.org/en/state/cameroon-CM

- UNESCO Oral Traditions and Expressions:
  https://ich.unesco.org/en/oral-traditions-and-expressions-00053

- UNESCO World Heritage — Cameroon:
  https://whc.unesco.org/en/statesparties/cm

### Secondary research sources

- Mythology/Folklore databases and other reputable academic or cultural sources may be added later through configuration.

Do not hard-code the crawler around only these websites. Design the source system so that additional sources can easily be added later.

---

# 2. Main Objective

The crawler should search the configured sources and identify information relevant to:

- Cultural stories
- Folktales
- Legends
- Myths
- Oral traditions
- Historical events
- Cultural traditions
- Festivals
- Rituals
- Traditional practices
- Artefacts
- Traditional clothing
- Traditional instruments
- Masks
- Sculptures
- Royal objects
- Archaeological objects
- Heritage sites
- Museums
- Cultural locations
- Cultural groups
- Languages
- Traditional arts and crafts
- Traditional food where sufficiently documented
- Cultural personalities
- Cultural institutions

The crawler must prioritize **Cameroonian content** and should not import unrelated African or international content unless the source clearly establishes a connection to Cameroon or the content is explicitly configured as relevant.

---

# 3. Crawling Strategy

Implement a configurable crawling pipeline:

SOURCE
↓
URL discovery
↓
Robots.txt / crawling-policy check
↓
Page download
↓
Content extraction
↓
Relevance detection
↓
Data normalization
↓
Duplicate detection
↓
Metadata extraction
↓
Source/provenance recording
↓
Validation status = PENDING_REVIEW
↓
Database insertion
↓
Admin review

Do not automatically publish crawled content to end users.

All newly imported cultural information must initially have a status such as:

PENDING_REVIEW

An administrator or authorized cultural contributor must be able to review and approve the content before it becomes publicly visible.

---

# 4. Information to Extract

For each cultural story, attempt to extract:

- title
- alternative title
- description
- full story/content
- cultural group
- ethnic/community association when explicitly stated by the source
- country
- region
- department/division when available
- locality
- cultural category
- historical period when available
- language
- themes
- keywords
- source URL
- source website
- author
- institution
- publication date
- date crawled
- images
- audio
- video
- related locations
- related artefacts
- references/citations

For artefacts, attempt to extract:

- name
- alternative names
- description
- object type
- cultural group
- region
- locality
- historical period
- material
- dimensions when available
- cultural significance
- historical significance
- museum/institution
- collection information
- current location
- images
- source URL
- author/institution
- publication date
- crawl date

Do not invent missing information.

If a field cannot be reliably extracted, store NULL or an equivalent empty value.

---

# 5. Provenance and Source Tracking

This is extremely important.

Every imported item must retain its source information.

Create or use a source/provenance structure containing at least:

- source_name
- source_url
- original_url
- source_type
- author
- institution
- publication_date
- crawled_at
- extraction_method
- license/copyright information when available
- attribution requirements when available
- confidence_score
- validation_status

The database must allow administrators to trace every piece of imported information back to its original source.

Never remove the original URL.

---

# 6. Copyright and Content Handling

Do NOT blindly copy entire copyrighted websites into the database.

Respect:

- robots.txt
- website terms of use
- copyright restrictions
- licenses
- attribution requirements
- rate limits

Where full-text storage is not appropriate, store:

- title
- metadata
- short factual summary
- source URL
- attribution
- relevant structured information

For images, audio, and video, determine whether the source permits reuse before downloading and storing the media.

If the license or reuse permission cannot be established, do not automatically redistribute the media.

Instead, store the original media URL and attribution information where appropriate.

---

# 7. Image and Media Extraction

When permitted, identify relevant:

- JPEG
- PNG
- WebP
- SVG
- MP3
- WAV
- MP4
- WebM
- PDF

For each media item store:

- original URL
- local storage path if downloaded
- media type
- file size
- source URL
- attribution
- license
- checksum/hash
- crawl date

Do not download advertisements, logos, tracking pixels, navigation images, icons, or unrelated website assets.

Images should be associated with the correct story, artefact, institution, or heritage location.

---

# 8. Relevance Detection

Implement a relevance scoring system.

Prioritize pages containing terms related to:

- Cameroon
- Cameroonian
- culture
- heritage
- folklore
- folktale
- tradition
- legend
- oral tradition
- artefact
- artifact
- museum
- indigenous
- festival
- ritual
- traditional
- archaeology
- heritage site
- cultural practice

Also detect Cameroon-related regions and cultural groups when explicitly mentioned.

Do not rely only on keywords.

Use the page context to determine whether the information is actually relevant.

---

# 9. Cultural Metadata

Where the source explicitly provides the information, normalize cultural metadata into structured fields.

Examples:

Country:
Cameroon

Regions:
- Centre
- Littoral
- West
- North-West
- South-West
- North
- Far North
- Adamawa
- East
- South

Possible cultural groups should only be assigned when supported by the source.

Do not infer a cultural group merely from the geographical location.

---

# 10. Deduplication

Implement strong duplicate detection.

Before inserting new information:

1. Compare source URL.
2. Compare normalized title.
3. Compare content similarity.
4. Compare artefact names.
5. Compare hashes for downloaded media.
6. Compare existing database records.

If an item already exists:

- do not create another duplicate record;
- update the existing record only when appropriate;
- preserve all relevant sources;
- maintain source relationships.

The same cultural story may legitimately have multiple sources, so do not treat different sources as duplicates merely because they describe the same cultural subject.

---

# 11. Database Integration

Integrate the crawler with my existing Django project.

First inspect the existing:

- Django models
- serializers
- views
- API endpoints
- database structure
- media handling
- authentication
- admin interface

Do not create duplicate models if equivalent models already exist.

Reuse existing models whenever possible.

If models need to be extended, explain the required changes before making destructive modifications.

The crawler should preferably insert data through a dedicated ingestion/service layer rather than directly manipulating unrelated application logic.

---

# 12. Suggested Data Model

If equivalent models do not already exist, create an ingestion structure similar to:

CulturalContent

- id
- title
- slug
- description
- content
- content_type
- category
- cultural_group
- country
- region
- locality
- language
- historical_period
- status
- created_at
- updated_at

Source

- id
- name
- base_url
- source_type
- reliability_level

SourceReference

- id
- content
- source
- original_url
- author
- institution
- publication_date
- crawled_at
- license
- attribution

Media

- id
- content
- media_type
- original_url
- local_path
- license
- attribution
- checksum

CrawlJob

- id
- source
- started_at
- completed_at
- status
- pages_processed
- items_found
- items_imported
- duplicates_found
- errors

CrawledItem

- id
- crawl_job
- original_url
- extracted_title
- extracted_content
- relevance_score
- processing_status
- error_message

Adapt these models to my existing architecture instead of blindly creating them.

---

# 13. Admin Workflow

The crawler must NOT automatically publish content.

Create the following workflow:

CRAWLED
→ EXTRACTED
→ NORMALIZED
→ PENDING_REVIEW
→ APPROVED
→ PUBLISHED

Possible rejection states:

REJECTED
NEEDS_CORRECTION

Administrators should be able to:

- view imported content
- view original source
- view extracted information
- view downloaded media
- edit metadata
- approve content
- reject content
- request correction
- remove imported content
- see when and from where the content was imported

---

# 14. Crawler Configuration

Create a configuration system so I can define:

- enabled sources
- crawl frequency
- maximum pages
- maximum depth
- allowed domains
- URL patterns
- excluded URL patterns
- request delay
- timeout
- maximum file size
- allowed media types
- relevance threshold
- language filters
- country filters

Example:

SOURCE = UNESCO
ENABLED = true
MAX_DEPTH = 3
DELAY = 2 seconds
COUNTRY = Cameroon
RELEVANCE_THRESHOLD = 0.70

Do not crawl aggressively.

Use polite request delays and caching where possible.

---

# 15. Error Handling

The crawler must handle:

- HTTP errors
- timeouts
- invalid URLs
- redirects
- malformed HTML
- missing metadata
- unavailable media
- duplicate content
- rate limiting
- robots.txt restrictions
- network failures
- parsing errors

A failure on one page must not stop the entire crawl.

Log every failure with:

- URL
- timestamp
- error type
- error message
- crawl job ID

---

# 16. Logging and Monitoring

Implement structured logs for:

- crawl start
- crawl completion
- pages visited
- pages skipped
- relevant pages
- content extracted
- duplicates
- media downloaded
- content imported
- content rejected
- errors

Provide a summary such as:

Crawl completed

Pages visited: 250
Relevant pages: 74
Stories extracted: 32
Artefacts extracted: 18
Heritage locations: 11
Media files: 43
Duplicates: 16
Rejected: 4
Errors: 7

---

# 17. Scheduling

If the existing project supports scheduled tasks, integrate the crawler with the existing task system.

Allow:

- manual crawling
- scheduled crawling
- source-specific crawling
- full crawl
- incremental crawl

Prefer incremental crawling so that already processed pages are not repeatedly downloaded unnecessarily.

---

# 18. API / Django Integration

Expose appropriate Django API endpoints for the administrative crawler functionality, for example:

POST /api/crawler/start/
GET /api/crawler/jobs/
GET /api/crawler/jobs/{id}/
GET /api/crawler/items/
GET /api/crawler/items/{id}/
POST /api/crawler/items/{id}/approve/
POST /api/crawler/items/{id}/reject/

Adapt endpoint names to the existing project conventions.

Only authorized administrators should be able to execute crawler management operations.

---

# 19. Flutter Integration

Do not expose raw crawler functionality to normal explorers.

Flutter should only receive content that has passed the appropriate validation and publication workflow.

The Explorer application should consume approved cultural content through the existing Django REST API.

The expected flow is:

Crawler
↓
Django ingestion layer
↓
Pending cultural content
↓
Administrator review
↓
Approved content
↓
Django REST API
↓
Flutter application
↓
Explorer

---

# 20. Security Requirements

Do not introduce security vulnerabilities.

In particular:

- validate downloaded files
- restrict file types
- enforce maximum file sizes
- sanitize extracted HTML
- prevent malicious content injection
- validate URLs
- prevent SSRF vulnerabilities
- restrict crawler domains
- authenticate crawler administration endpoints
- protect administrative actions
- never execute downloaded code
- never trust external metadata
- sanitize filenames
- use safe media storage

Do not allow arbitrary external URLs to be fetched through an unrestricted API endpoint.

---

# 21. Important Cultural Integrity Requirement

The crawler must distinguish between:

1. Information directly supported by the source.
2. Information inferred by the system.
3. AI-generated summaries.

Never present inferred or AI-generated information as an established cultural fact.

Whenever AI is used for summarization or classification, retain the original source and extracted information.

The administrator must be able to inspect the original source before approving content.

---

# 22. Development Process

Before modifying the code:

1. Inspect the current crawler implementation.
2. Inspect the Django project structure.
3. Inspect existing models.
4. Inspect the database schema.
5. Inspect existing media storage.
6. Inspect API architecture.
7. Identify reusable components.
8. Identify conflicts with the proposed crawler.
9. Provide a concise implementation plan.

Do not rewrite the project unnecessarily.

Do not replace existing functionality without justification.

After implementation:

1. Run migrations if necessary.
2. Run unit tests.
3. Test crawling against each configured source.
4. Test duplicate detection.
5. Test media extraction.
6. Test source/provenance tracking.
7. Test admin approval workflow.
8. Test API integration.
9. Test security restrictions.
10. Provide a summary of all modifications.

The final result should be a **maintainable, configurable, respectful, source-aware cultural heritage ingestion system for Griot AI**, rather than a simple web scraper.