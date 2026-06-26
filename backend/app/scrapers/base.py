"""Base scraper contract. Each source returns a list of normalized job dicts.

Normalized shape:
{
  "source": str, "ext_id": str, "title": str, "company": str,
  "location": str, "url": str, "description": str,
  "tags": [str], "salary": str, "posted_at": str
}
"""
import re
import requests

UA = "Mozilla/5.0 (CareerAI/1.0; +https://github.com/careerai) python-requests"
TIMEOUT = 12


def http_get(url, params=None, headers=None):
    h = {"User-Agent": UA, "Accept": "application/json"}
    if headers:
        h.update(headers)
    resp = requests.get(url, params=params, headers=h, timeout=TIMEOUT)
    resp.raise_for_status()
    return resp


_TAG = re.compile(r"<[^>]+>")
_WS = re.compile(r"\s+")


def strip_html(text: str) -> str:
    if not text:
        return ""
    text = _TAG.sub(" ", text)
    text = (text.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
                .replace("&nbsp;", " ").replace("&#39;", "'").replace("&quot;", '"'))
    return _WS.sub(" ", text).strip()


class BaseScraper:
    name = "base"

    def fetch(self, query: str = "", location: str = "") -> list:
        raise NotImplementedError
