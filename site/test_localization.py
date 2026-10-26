"""Static checks for the bilingual ntfy-native product page."""
from html.parser import HTMLParser
from pathlib import Path
import unittest

ROOT = Path(__file__).parent

class Links(HTMLParser):
    def __init__(self):
        super().__init__(); self.footer = False; self.switches = []
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "footer": self.footer = True
        if self.footer and tag == "a" and "data-language" in a:
            self.switches.append(a)
    def handle_endtag(self, tag):
        if tag == "footer": self.footer = False

class LocalizationTests(unittest.TestCase):
    def test_chinese_root_has_footer_link_to_english(self):
        text = (ROOT / "index.html").read_text()
        self.assertIn('<html lang="zh-CN">', text)
        links = Links(); links.feed(text)
        self.assertEqual(len(links.switches), 1)
        self.assertEqual(links.switches[0].get("data-language"), "en")
        self.assertIn("让消息", text)

    def test_english_copy_has_footer_link_to_chinese(self):
        text = (ROOT / "en" / "index.html").read_text()
        self.assertIn('<html lang="en">', text)
        links = Links(); links.feed(text)
        self.assertEqual(len(links.switches), 1)
        self.assertEqual(links.switches[0].get("data-language"), "zh")
        self.assertIn("Messages,", text)

    def test_english_page_assets_resolve_from_the_locale_subdirectory(self):
        text = (ROOT / "en" / "index.html").read_text()
        self.assertIn('href="../assets/site.css"', text)
        self.assertIn('src="../assets/site.js"', text)
        self.assertIn('src="../assets/app-icon.png"', text)

    def test_root_uses_shared_preference_before_browser_fallback(self):
        text = (ROOT / "index.html").read_text()
        self.assertIn("site_lang", text)
        self.assertIn("navigator.languages", text)
        self.assertRegex(text, r"location\.replace\([\"']?/ntfy-native/en/[\"']?\)")

    def test_root_uses_ip_country_before_browser_fallback(self):
        text = (ROOT / "index.html").read_text()
        self.assertIn("/cdn-cgi/trace", text)
        self.assertIn("1200", text)  # bounded wait, then browser fallback
        # IP preference must not override an explicit saved choice.
        self.assertLess(text.index("if(saved){apply(saved);return;}"), text.index("/cdn-cgi/trace"))

    def test_demo_script_localizes_inserted_messages(self):
        text = (ROOT / "assets" / "site.js").read_text()
        self.assertIn("document.documentElement.lang", text)
        self.assertIn("刚刚", text)
        self.assertIn("Just now", text)
        self.assertIn("Nothing was sent over the network", text)

if __name__ == "__main__":
    unittest.main()
