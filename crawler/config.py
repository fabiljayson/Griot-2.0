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
# Content type = what KIND OF PAGE this was: a kingdom, a landmark, a legend.
# Distinct from material type (config.MATERIAL_TYPE_KEYWORDS), which is what
# the object is. A carved mask is content type "Artifact" and material type
# "mask" at once, so these cannot share one field.
CONTENT_TYPE_KEYWORDS = {
    "Kingdom": [
        "kingdom", "palace", "sultan", "sultanate", "royal", "chief",
        "bandjoun", "baham", "bangoulap", "batoufam", "bamoun",
        "bamileke", "grassland people", "feudal", "dynasty",
    ],
    "Landmark": [
        "monument", "memorial", "statue", "fountain", "castle",
        "courthouse", "temple", "church", "mosque", "bridge",
        "colonial building", "reunification", "museum",
    ],
    "Artifact": [
        "artifact", "artwork", "sculpture", "mask",
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

# Material type = what the object is. These values are the backend's
# qr_codes.Artifact.Category choices, lowercased, so the crawler can emit them
# directly without a lossy mapping on the way in.
MATERIAL_TYPE_KEYWORDS = {
    "sculpture": [
        "sculpture", "statue", "statuette", "carving", "carved figure",
        "bas-relief", "relief", "effigy", "figurine", "wood carving",
    ],
    "instrument": [
        "drum", "xylophone", "balafon", "horn", "flute", "rattle",
        "musical instrument", "kenkeni", "mbira", "ngon", "talking drum",
    ],
    "pottery": [
        "pottery", "pot", "vase", "terracotta", "ceramic", "earthenware",
        "water jar", "cooking pot", "clay pot",
    ],
    "mask": ["mask", "masquerade", "helmet mask", "wooden mask"],
    "textile": [
        "textile", "cloth", "cotton", "embroidery", "embroidered",
        "wrapper", "garment", "attire", "clothes",
    ],
    "jewelry": [
        "necklace", "bracelet", "bead", "beads", "earring", "bangle",
        "jewelry", "jewellery", "anklet",
    ],
    "weapon": [
        "spear", "sword", "dagger", "shield", "knife", "cutlass",
        "matchet", "war axe", "machete",
    ],
    "fabric": [
        "fabric", "raffia", "fibre", "fiber", "mat", "basket",
        "weaving", "loom", "woven", "plaited", "plait",
    ],
    "tool": [
        "tool", "hoe", "fishing net", "agricultural implement", "farm tool",
        "gourd", "calabash", "container", "weaving tool",
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