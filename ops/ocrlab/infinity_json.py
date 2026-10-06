"""infinity_json.py — Infinity-Parser2's layout prompt, and its JSON answer reduced to plain text.

The model is RL-tuned for one prompt (its MLX build's card says another "may yield unexpected output"),
which asks for a JSON object of layout elements, each with a bbox, a category and its text. json_text keeps
the text of every element in the order given, figures being empty by the prompt's own rule. A read cut off
by the time or token limit does not parse, so then every complete "text" string is taken in order instead.
"""
import json, re

PROMPT = """- Extract layout information from the provided PDF image.
- For each layout element, output its bbox, category, and the text content within the bbox.
- Bbox format: [x1, y1, x2, y2].
- Allowed layout categories: ['header', 'title', 'text', 'figure', 'table', 'formula', 'figure_caption', 'table_caption', 'formula_caption', 'figure_footnote', 'table_footnote', 'page_footnote', 'footer'].
- Text extraction and formatting:
  1) For 'figure', the text field must be an empty string.
  2) For 'formula', format text as LaTeX.
  3) For 'table', format text as HTML.
  4) For all other categories (e.g., text, title), format text as Markdown.
- The output text must be exactly the original text from the image, with no translation or rewriting.
- Sort all layout elements in human reading order.
- Final output must be a single JSON object."""

_TEXT = re.compile(r'"text"\s*:\s*("(?:[^"\\]|\\.)*")')


def _elements(obj):
    """Every dict carrying a "text" field, in document order, whatever the object's outer shape."""
    if isinstance(obj, dict):
        if "text" in obj and isinstance(obj["text"], str):
            yield obj
        else:
            for v in obj.values():
                yield from _elements(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from _elements(v)


def json_text(answer):
    s = answer.strip()
    if s.startswith("```"):
        s = s.split("\n", 1)[1] if "\n" in s else ""
        s = s.rsplit("```", 1)[0]
    try:
        return "\n".join(e["text"] for e in _elements(json.loads(s)) if e["text"].strip())
    except ValueError:
        pieces = []
        for m in _TEXT.finditer(s):
            try:
                pieces.append(json.loads(m.group(1)))
            except ValueError:
                continue
        return "\n".join(p for p in pieces if p.strip())


if __name__ == "__main__":
    whole = '```json\n{"layout": [{"bbox": [1, 2, 3, 4], "category": "title", "text": "A \\"B\\""},' \
            ' {"bbox": [1], "category": "figure", "text": ""}, {"category": "text", "text": "c\\nd"}]}\n```'
    assert json_text(whole) == 'A "B"\nc\nd', json_text(whole)
    cut = '[{"category": "text", "text": "one"}, {"category": "text", "text": "two"}, {"text": "thr'
    assert json_text(cut) == "one\ntwo", json_text(cut)
    print("ok")
