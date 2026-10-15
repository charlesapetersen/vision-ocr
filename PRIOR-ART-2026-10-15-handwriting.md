# PRIOR-ART-2026-10-15 — small local models for handwritten pages

Owner, 2026-10-15: "Are there any small local models focused specifically on handwriting recognition that might be
worth considering along with Qwen for Vision-OCR? Have we looked before? If not, do research, be thorough." Two web
surveys (subagents) that day: one of page-level vision-language models, one of specialist line-level handwriting
recognisers. Figures marked [checked] were opened at the source by the survey; the four repos and the NARA table
in §2 were re-read by the interactive session through the Hugging Face API. Nothing here is a measurement on this
project's truth set. Follows `PRIOR-ART-2026-10-07.md`, which surveyed print.

## 1. What had been looked at before

Only print. The 7 October survey and bake-off were about newspapers and typescript, and the bake-off left
handwritten words out of its scoring. Churro 3B (`churro-3b-8bit`, 5.8 GB peak) and `nara-qwen-3.5-2b-4bit` were
both run in the lab on print and newspapers, never scored on handwriting. Qwen3.5-9B 4-bit was tried on 8 pages
and dropped by the owner as weak on old print; its one ordinary page peaked at 8,945 MB and took 57 s
(`$STATE/ocrlab/qwen9b.try`). The lab's weights for all of these have since been deleted.

What this project measured on handwriting (HW-MEASURE-2026-10-15.tsv, 19 handwritten pages of Archive Suite's
truth set, missed words per 1,000): Vision 561, PaddleOCR-VL 454, Falcon-OCR 409. Archive Suite's hosted panel
(`ocr-panel-local-groups.csv`, 16 originals labelled handwritten, words missed): Vision 57%, Qwen3.5-9B 7.7%,
Qwen3.6-27B 6.6%, Gemma 4 31B 7.8%, Qwen3-VL-8B 12.3%. Those ran at bf16 on OpenRouter, not as Mac builds.

## 2. Page-level models

**LightOnOCR-3-4B** (`lightonai/LightOnOCR-3-4B`, created 6 Oct 2026, Apache-2.0, 4.5B, Qwen3.5 architecture)
[checked, API]. The strongest new candidate. On the NARA pension-file holdout (762 pages from 39 documents not in
training, 18th–19th century American cursive and forms), scored by W. Mattingly, not LightOn
(`wjbmattingly/nara-lightonocr-3-4b`, its README table) [checked, re-read]: stock LightOnOCR-3-4B with that repo's
`prompt.txt` CER 0.2057; the NARA fine-tune of the same model 0.2312; `nara-lightonocr-3-0.8b` 0.2550;
`nara-qwen-3.5-2b` 0.2688. The card says the same weights scored 0.2332 on a different GPU type and to treat gaps
under about 0.03 as ties, and recommends the stock model. LightOn's own figures [checked: HF blog]: fr-bench
handwritten 46.1 (Chandra 2 26.1, Surya 2 2.4), olmOCR-bench "Old scans" 52.5. Its `grounding` prompt returns
labelled blocks with boxes on a 0–1000 scale, block-level rather than line-level. MLX builds:
`prithivMLmods/LightOnOCR-3-4B-MLX` (4- and 8-bit, created 8 Oct 2026 [checked, API]), `BaranH/LightOnOCR-3-4B-mlx-4Bit`
and `-8Bit`; GGUF from mradermacher and prithivMLmods. Whether they run under this lab's mlx-vlm is unverified.
Smaller siblings 0.8B and 1B score 33.3 and 37.0 on fr-bench handwritten, and the 0.8B scored a poor 0.4185 on
NARA zero-shot.

**Churro 3B** (`stanford-oval/churro-3B`, Oct 2025, Qwen research licence, non-commercial, 3B). Still first among
open models on CHURRO-DS handwritten, 70.1 normalised Levenshtein similarity, ahead of Gemini 3.1 Pro 68.3 and
Gemini 3 Pro 66.7; English handwritten 84.0 against Gemini 3.1 Pro's 86.3 [checked: the leaderboard's
benchmark_results.json; the authors' own benchmark]. An independent check by Teklia on French 16th–18th century
parish records: Churro CER 22.2%, Qwen3.5-9B 44.6%, Claude Opus 4.5 20.2% [checked: the
`Teklia/Qwen2.5-VL-7B-DAI-CReTDHI-RecordGold-ATR` card]. No boxes. The lab converted it to MLX 8-bit itself on
7 Oct; `kintopp/churro-mlx` is on GitHub (the Hugging Face URL returns 401).

**Qwen3.5-9B itself has mixed evidence.** CHURRO handwritten 42.4, English 69.2. socOCRbench handwritten text 0.4052,
below Qwen3.5-4B 0.4522 and Qwen3.5-2B 0.4313 [checked: noahdasanaike.github.io/posts/sococrbench.html, 280 pages
from five regions, not English-specific]. Teklia's French records 44.6% CER, as above. Against that, Archive
Suite's panel on this collection's own pages had it missing 7.7% of words.

**Others with handwriting evidence, not shortlisted.** dots.mocr (MIT, 3B, CHURRO handwritten 55.0, English 69.2,
gives layout boxes; MLX builds exist). Surya OCR 2 (about 650M, OpenRAIL-M with revenue limits; best small model
on socOCRbench handwritten at 0.5543, but 2.4 on LightOn's fr-bench; the two disagree). Chandra 2 (5.3B, OpenRAIL-M,
fr-bench handwritten 26.1). On CHURRO handwritten: Qwen3-VL-8B 48.5, NuMarkdown-8B 51.2, RolmOCR 49.0, olmOCR-2-7B
44.6, GLM-OCR 40.2, PaddleOCR-VL 1.5 33.6, DeepSeek-OCR-2 20.0, Phi-4-multimodal 5.3. Falcon-OCR v1.5's notes claim
better handwriting with no score [unverified]. Datalab says its Indra OCR does not read handwriting.

**Line-level fine-tunes on chat models** (would need a line segmenter first): Barbados 17th–18th century English
deed models from a Zindi competition (Qwen3.5-9B/4B, Qwen3-VL-8B and Qwen2.5-VL-7B LoRAs),
`wjbmattingly/LightOnOCR-2-1B-cultural-heritage-english`.

## 3. Specialist handwriting recognisers

**Kraken 7.1's PP-OCRv6 base models** (`small-models-for-glam/kraken-ppocrv6-medium`, created 3 Sep 2026 [checked,
API]; Zenodo 21788410, 4 Aug 2026; Apache-2.0). The only specialist worth measuring. Medium is about 16M parameters,
a 64 MB file, a CTC line recogniser at 128 px line height, so it reads line crops and needs a segmenter for whole
pages. Trained on 44 languages, handwriting and print, weighted to English, French, German and Latin; the English
sources include IAM, JosephHookerHTR (19th century letters), Revolutionary City (18th century English hands, about
95k lines) and Memorials for Jane Lathrop Stanford. Reported CER on a held-out 5% of its own sources: English 5.90%
(WER 20.35%); small and tiny average 5.43% and 8.71%. PyTorch through pip, macOS on ARM supported; MPS support
unverified, and at this size the CPU is enough. No Core ML or ONNX export found.

**Party** (Kraken's page-level recogniser, `github.com/mittagessen/party`, Zenodo 20642057, Jun 2026, Apache-2.0,
518 MB). Reads a whole page given line positions; English CER 7.63% in-domain. Its examples use CUDA and Mac
support is not mentioned. Weaker than PP-OCRv6 and less Mac-friendly.

**TrOCR handwritten** (Microsoft, 62M to 558M; IAM line CER 4.22 to 2.89). Trained on IAM only, which is modern
forms; no published out-of-domain figure for historical English was found in two searches. ONNX builds exist
(`Xenova/trocr-base-handwritten`). The nearest historical fine-tune, `Kansallisarkisto/multicentury-htr-model`,
is Finnish and Swedish.

**Not worth the effort:** PyLaia (IAM CER 8.44%), Loghi (TensorFlow, Linux only, mostly Dutch), PERO-OCR (no public
handwriting model), DTrOCR (no weights), HTR-VT, HTR-ConvText, OrigamiNet, VAN, DAN (research models on IAM, RIMES
and READ 2016), McCATMuS (superseded by PP-OCRv6). Teklia's recent uploads are Qwen2.5-VL-7B fine-tunes rather
than new specialist models, which says where the field has moved.

## 4. Specialists against chat models

- Crosilla, Klic and Colavizza, arXiv 2503.15195 (Jun 2025) [checked], CER on Bentham (English, 18th–19th
  century): Transkribus Text Titan I 7.07%, Qwen2-VL-7B 8.01%, GPT-4o-mini 9.48%. Bentham was in Transkribus's
  pre-training.
- Humphries et al., arXiv 2411.03340 (Nov 2024) [checked: abstract]: chat models 5.7–7% CER on 18th–19th century
  English handwriting, about 14% better than Transkribus.
- Humphries, "Gemini 3 Solves Handwriting Recognition" (Nov 2025) [checked]: 50 English documents, strict CER
  Gemini 3 Pro 1.67%, Claude Opus 4.5 4.28%.
- Transkribus's own Text Titan I benchmark (Jun 2025) [checked: vendor blog]: English 11.5% CER on 2,000 held-out
  pages. Text Titan II (Jun 2026) claims about 47% lower, with no English figure [unverified].

So a two-generation-old 7B chat model was already level with the best specialist on English historical hands, and
current ones are ahead. A specialist's case here is exact line positions, speed and memory, and that it does not
invent fluent text, not accuracy.

## 5. What follows for this project

Measure four on the 19 handwritten pages, on this Mac: Qwen3.5-9B, LightOnOCR-3-4B (its empty default prompt and
Mattingly's `prompt.txt`), Churro 3B, and Kraken PP-OCRv6 medium reading Vision's line crops. Before Kraken, count
how many truth words fall inside a Vision line box on these pages: a line reader cannot read a line Vision missed,
and cursive whose ascenders and descenders touch, slanted lines and marginalia all break box detection. Kraken's
own baseline segmenter is the alternative if coverage is poor. Queued as `hw-qwen` (owner, 2026-10-15).

Key links: huggingface.co/lightonai/LightOnOCR-3-4B · huggingface.co/wjbmattingly/nara-lightonocr-3-4b ·
huggingface.co/stanford-oval/churro-3B · stanford-oval.github.io/Churro · huggingface.co/small-models-for-glam/kraken-ppocrv6-medium ·
zenodo.org/records/21788410 · github.com/mittagessen/party · noahdasanaike.github.io/posts/sococrbench.html ·
arxiv.org/abs/2503.15195 · arxiv.org/abs/2411.03340 · arxiv.org/abs/2509.19768
