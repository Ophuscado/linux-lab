"""The code-edit request of the speculation tests: llama-server on port ARGV[1] renames a variable in the
script ARGV[2], greedy; prints generation t/s, tokens, drafted and accepted counts and the md5 of the text
(reasoning and answer)."""
import hashlib, json, sys, urllib.request

src = open(sys.argv[2]).read()
msg = "Rename the shell variable M to MODEL everywhere in this script and change nothing else. Output only the full script.\n\n" + src
req = {"messages": [{"role": "user", "content": msg}], "temperature": 0, "max_tokens": 1500, "seed": 1}
r = json.load(urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{sys.argv[1]}/v1/chat/completions",
    json.dumps(req).encode(), {"Content-Type": "application/json"}), timeout=900))
t = r.get("timings", {})
m = r["choices"][0]["message"]
# Reasoning models (Gemma 4, GPT-OSS) may spend all 1500 tokens in reasoning_content and leave content empty
# (md5 d41d8cd9 for every setting on macOS, 27 Oct): the hash covers both, so settings stay comparable.
txt = (m.get("reasoning_content") or "") + "\0" + (m.get("content") or "")
print(f"gen {t.get('predicted_per_second', 0):.1f} t/s, {t.get('predicted_n')} tokens, drafted {t.get('draft_n')} "
      f"accepted {t.get('draft_n_accepted')}, text {hashlib.md5(txt.encode()).hexdigest()[:8]}")
