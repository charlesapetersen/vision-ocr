"""churro_xml.py — the plain text of one Churro reading (ocr-lab-round2).

Churro answers in HistoricalDocument XML. xml_text() takes its text the way the Churro repo's
tooling/evaluation/xml_utils.py::extract_actual_text_from_xml does (fetched 2026-10-05), with one
change: where that returns "" for XML that does not parse, this strips the tags instead, because a
read cut off by max_tokens is unparseable and its words are still words. `python churro_xml.py <file>`
prints the text of a saved reading.
"""
import html, re, sys
import xml.etree.ElementTree as ET


def _local_name(tag):
    return tag.rsplit("}", 1)[1] if "}" in tag else tag


def _remove_tag(s, name):
    if f"<{name}" not in s:
        return s
    s = re.sub(rf"<{name}\b[^>]*>.*?</{name}>", "", s, flags=re.DOTALL)
    return re.sub(rf"<{name}\b[^>]*/>", "", s)


def _strip_tags(s):
    s = _remove_tag(s, "Description")
    s = re.sub(r"<[^>]*>?", "\n", s)
    lines = [l.strip() for l in s.splitlines()]
    return html.unescape("\n".join(l for l in lines if l))


def xml_text(s):
    if "HistoricalDocument" not in s:
        return s
    for name in ("Description", "Deletion", "Illegible", "Gap"):
        s = _remove_tag(s, name)
    # The model sometimes wraps its answer in a ```xml fence.
    m = re.search(r"<HistoricalDocument\b.*</HistoricalDocument>", s, flags=re.DOTALL)
    try:
        root = ET.fromstring(m.group(0) if m else s)
    except ET.ParseError:
        return _strip_tags(s)
    pages = []
    for page in root.iter():
        if _local_name(page.tag) != "Page":
            continue
        sections = []
        for child in page.iter():
            if _local_name(child.tag) not in {"Header", "Body", "Footer"}:
                continue
            lines = [l.strip() for l in child.itertext() if l.strip()]
            if lines:
                sections.append("\n".join(lines))
        if sections:
            pages.append("\n".join(sections))
    return "\n\n".join(pages).strip()


if __name__ == "__main__":
    print(xml_text(open(sys.argv[1]).read()))
