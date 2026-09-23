# Role & Objective

## Completed Work Summary

### 1. Web Crawler (✅ Complete)
- Built Python crawler for discover-cameroon.com
- Extracted 127 artifacts with stories, categories, and locations
- Downloaded 137 images to `downloads/images/`
- Output: `downloads/cameroon_content.json`

### 2. Django Artifacts App (✅ Complete)
- Created `artifacts` app with auto QR code generation
- Model: `title`, `slug`, `category`, `location`, `story`, `historical_significance`, `source_url`, `audio_file`, `video_url`, `qr_code`
- QR codes auto-generated on save (PNG format, terracotta brand color)
- Mobile-first template with Tailwind CSS

### 3. Data Import (✅ Complete)
- Management command: `python manage.py import_crawl_data`
- 127 artifacts imported with stories, categories, locations
- 127 QR codes auto-generated
- 107 images downloaded to `media/artifacts/images/`

### 4. Color Palette (✅ Complete)
Applied unified Cameroonian heritage color palette:

| Color | Hex | Usage |
|-------|-----|-------|
| cam-indigo | #1E2B58 | Primary headers, navigation |
| cam-bronze | #C68B29 | CTAs, active states, audio controls |
| cam-earth | #A0382B | Historical alerts, badges |
| cam-green | #1B4332 | Success states, location tags |
| cam-ivory | #FBF9F4 | Background canvas |
| cam-white | #FFFFFF | Cards, surfaces |
| cam-dark | #1C1C1E | Body text |

Design rules (60-30-10):
- 60% Neutral: cam-ivory backgrounds, cam-white cards
- 30% Structural: cam-indigo headers, navigation
- 10% Accents: cam-bronze CTAs, cam-earth badges

## File Structure

```
backend/
├── artifacts/           # NEW: Artifact model with auto QR generation
│   ├── models.py        # Artifact model
│   ├── admin.py         # Admin with QR preview & download
│   ├── views.py         # Artifact detail view
│   ├── urls.py          # URL routing
│   └── management/
│       └── commands/
│           └── import_crawl_data.py  # Import crawl JSON
├── templates/
│   └── artifacts/
│       └── detail.html  # Mobile-first QR landing page
└── media/
    ├── artifacts/       # Crawl images
    └── qr_codes/        # Auto-generated QR PNGs

crawler/
└── main.py              # Web crawler script

downloads/
├── cameroon_content.json  # 127 artifacts
└── images/                # 137 downloaded images
```

## How to Use

### Run the Crawler
```bash
python crawler/main.py              # Full crawl + download
python crawler/main.py --dry-run    # Crawl only
```

### Import Data to Django
```bash
cd backend
python manage.py import_crawl_data
```

### Access in Browser
- Home: `http://localhost:8000/`
- Artifacts: `http://localhost:8000/artifacts/`
- Artifact Detail: `http://localhost:8000/artifacts/<slug>/`
- Admin: `http://localhost:8000/admin/`
