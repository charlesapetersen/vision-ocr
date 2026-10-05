"""drop-weights.py <hf-repo>… — delete a candidate's downloaded weights from the lab's HF cache.

The item deletes a candidate that does not fit, and the lab stays under 25 GB; this goes through
huggingface_hub's own cache API, so it can only remove what the lab downloaded into $HF_HOME.
"""
import sys
from huggingface_hub import scan_cache_dir

cache = scan_cache_dir()
want = set(sys.argv[1:])
hashes = [rev.commit_hash for repo in cache.repos if repo.repo_id in want for rev in repo.revisions]
found = {repo.repo_id for repo in cache.repos if repo.repo_id in want}
for r in sorted(want - found): print(f"drop-weights: {r} not in the cache", file=sys.stderr)
if hashes:
    plan = cache.delete_revisions(*hashes)
    print(f"drop-weights: freeing {plan.expected_freed_size_str} from {', '.join(sorted(found))}")
    plan.execute()
