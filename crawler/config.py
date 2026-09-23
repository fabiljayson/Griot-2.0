"""Central configuration and static datasets for the Cameroon crawler."""

from pathlib import Path

BASE_URL = "https://discover-cameroon.com"
REQUEST_DELAY = 1.5  # seconds between page requests
IMAGE_DOWNLOAD_WORKERS = 5
IMAGE_MIN_SIZE = 200  # min width or height in px
REQUEST_TIMEOUT = 20
MAX_RETRIES = 3

DEFAULT_OUTPUT_DIR = Path(__file__).resolve().parent.parent / "downloads"

# Pages to crawl mapped to their primary category context
PAGES_TO_CRAWL = [
    # Main content pages
    {"url": "/en/about-cameroon/", "type": "overview"},
    {"url": "/en/attractions/", "type": "attractions"},
    {"url": "/en/tours/", "type": "tours"},
    # Regional / city pages
    {"url": "/en/foumban-en/", "type": "region", "default_location": "Foumban, West Region"},
    {"url": "/en/douala/", "type": "region", "default_location": "Douala, Littoral Region"},
    {"url": "/en/history/", "type": "content", "default_location": "Cameroon"},
    {"url": "/en/culture-languages-religions/", "type": "content", "default_location": "Cameroon"},
    {"url": "/en/limbe/", "type": "region", "default_location": "Limbe, Southwest Region"},
    {"url": "/en/buea-en/", "type": "region", "default_location": "Buea, Southwest Region"},
    {"url": "/en/bamenda/", "type": "region", "default_location": "Bamenda, Northwest Region"},
    {"url": "/en/kribi/", "type": "region", "default_location": "Kribi, South Region"},
    {"url": "/en/things-to-do-in-cameroon/", "type": "content", "default_location": "Cameroon"},
    # Additional city/region pages
    {"url": "/en/yaounde/", "type": "region", "default_location": "Yaoundé, Centre Region"},
    {"url": "/en/garoua/", "type": "region", "default_location": "Garoua, North Region"},
    {"url": "/en/rhumsiki/", "type": "region", "default_location": "Rhumsiki, Far North Region"},
    {"url": "/en/bertoua/", "type": "region", "default_location": "Bertoua, East Region"},
    {"url": "/en/dschang-en/", "type": "region", "default_location": "Dschang, West Region"},
    {"url": "/en/ngaoundere-en/", "type": "region", "default_location": "Ngaoundéré, Adamawa Region"},
    # Special topic pages
    {"url": "/en/cameroon-national-parks/", "type": "content", "default_location": "Cameroon"},
    {"url": "/en/cameroon-regions/", "type": "content", "default_location": "Cameroon"},
    {"url": "/en/food-and-drinks/", "type": "content", "default_location": "Cameroon"},
    {"url": "/en/climate-geographie/", "type": "content", "default_location": "Cameroon"},
    {"url": "/en/general-informations/", "type": "content", "default_location": "Cameroon"},
]

# Category keywords for auto-classification
CATEGORY_KEYWORDS = {
    "Kingdom": [
        "kingdom", "palace", "sultan", "sultanate", "royal", "chief",
        "bandjoun", "baham", "bangoulap", "batoufam", "bamoun",
        "bamileke", "grassland people", "feudal", "dynasty",
    ],
    "Landmark": [
        "monument", "memorial", "statue", "fountain", "castle",
        "courthouse", "temple", "church", "mosque", "bridge",
        "colonial building", "reunification",
    ],
    "Artifact": [
        "museum", "artifact", "artwork", "sculpture", "mask",
        "craft", "carving", "pottery", "textile", "work of art",
    ],
    "Legend": [
        "legend", "myth", "crater lake", "sacred", "mystical",
        "magical", "supernatural", "never hits the water",
    ],
    "Culture": [
        "culture", "tradition", "festival", "ceremony", "language",
        "religion", "ethnic", "people", "pygmy", "ba'aka", "bayaka",
        "fang-beti", "coastal people", "sudano-sahelian",
    ],
}

# Region -> location string mapping
REGION_LOCATIONS = {
    "foumban": "Foumban, West Region",
    "douala": "Douala, Littoral Region",
    "limbe": "Limbe, Southwest Region",
    "buea": "Buea, Southwest Region",
    "bamenda": "Bamenda, Northwest Region",
    "kribi": "Kribi, South Region",
    "yaounde": "Yaoundé, Centre Region",
    "garoua": "Garoua, North Region",
    "rhumsiki": "Rhumsiki, Far North Region",
    "bertoua": "Bertoua, East Region",
    "dschang": "Dschang, West Region",
    "ngaoundere": "Ngaoundéré, Adamawa Region",
}

# Headings to skip (footer/nav)
SKIP_HEADINGS = {
    "follow & like us :", "our products", "our tours", "languages",
    "terms & conditions", "impressum", "privacy policy", "privacy overview",
    "discover our tours", "book your tours", "cameroon attractions",
    "follow & like us", "discover our tours",
}