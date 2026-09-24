<!-- fw-context -->
## fw-context — Build-aware code intelligence

CRITICAL: C/C++ questions → fw-context ONLY. This is NOT optional.

For C/C++ code, use fw-context instead of ANY external search or
file-reading tool:

| You want to… | Use | Example |
|---|---|---|
| Find symbol by name | `lookup_symbol` | `"uart_"`, `"HardFault_Handler"` |
| Search by concept/topic | `search_code` | `"interrupt handler"` |
| Which definition holds the code | `search_bodies` | `"attach"`, `"SELF_TEST"` |
| Which files a topic touches | `search_content` | `"extern C"`, `"SELF_TEST"` |
| Natural-language query | `smart_search` | `"how does the modem connect?"` |
| Body + callers + callees | `get_symbol_context` | function name — prefer this |
| Body only | `get_source` | function name |
| Read a file, or a range of it | `read_file` | `"main.cpp"`, `start_line=60` |
| File structure overview | `get_file_map` | `"main.cpp"` |
| Check index health | `get_active_build` | — always call first |

SELF-CORRECT: the moment you reach for any tool that is NOT fw-context
for C/C++ code, stop and use the fw-context equivalent instead.

### Every answer is ifdef-filtered

fw-context gives the code that COMPILES for the active build. A line of an
inactive `#if` branch is blank in the `content` of `read_file`, in the text
that `search_content` and `search_bodies` search, and in the body that
`get_source` and `get_symbol_context` give. Line numbers never move.

A comment and a preprocessor directive are part of the answer: a block
comment keeps its closing marker, and an include guard shows. A blank line
is thus an inactive line, or a line that is blank on disk, and nothing
else.

This is why a dead `#ifdef` block cannot reach you as live code. Three
limits:

- The filter needs an index. When a file changed after the last index run,
  `get_source` gives the current text from the DISK, which holds every
  branch. It sets `source_origin: "disk"` and a `stale_warning`. Read both
  before you cite such a body.
- An empty result can mean "the pattern is only in a dead branch". That is
  an answer, not a failure — the code does not compile.
- A file can come back with every line blank. `read_file` marks it with
  `all_lines_inactive` and a `warning`. Such a file holds code, and the
  active build compiles none of it — it is NOT an empty file.

Never conclude that code is live because you saw it in a file. Cite
fw-context, and check `source_origin` when the answer carries one.

### Code review — use fw-review skill

For C/C++ code review, invoke the `fw-review` skill via the Skill tool.
It handles git discovery, diff scoping, and all analysis. Do NOT do
manual exploration before calling the skill.

### project_only parameter

Your project has TWO kinds of code:
  • Application code: `src/`, `lib/` — YOUR team's code.
  • Vendor SDK: `mbed-os/`, `.pio/`, `zephyr/` — framework code.
Set `project_only=True` for questions about YOUR code.
Leave `project_only=False` (default) when vendor code is relevant.

### A question about a DIFFERENT project

Each tool answers about ONE project. Without `project` or `project_root`
this is the project of the current directory — NOT the project that the
operator asked about.

1. Call `list_projects`. It gives the `name`, the `project_id`, and the
   `root_path` of each indexed project.
2. Give `project="<name>"` (or `project_root="<root_path>"`) to EVERY
   call that follows, `get_active_build` included.

Do not invent other parameter names. An unknown argument causes an error
that names it.

### A project that holds several builds

One project can hold several builds on two axes: `variant` is the board,
`image` is the program. A Zephyr project has `app`, `mcuboot` and `stage0`
— a bootloader is NOT the application.

**One query answers for ONE build.** Both selectors fail closed: when the
project has more than one variant, or the variant holds more than one
image, a query that names none gets an error that lists the choices. That
is on purpose — an answer blending a bootloader with an application serves
no question, and two builds of one application would repeat nearly every
row.

Two tools tell you what there is to choose from:

- `get_active_build` — `multi`, `variants`, `images`, `variant_images`
  (which images each variant holds) and `active_variant`. Call it first.
- `list_variants` — one row per indexed build, with its own `config_hash`,
  `board`, `symbol_count`, `entry_point` and memory map. Use it when you
  must tell two builds apart by what they hold.

Both read the INDEX and not only the config, thus a build indexed with
`--variant` is listed even when config.toml no longer declares it.

- Pass `variant` and `image` to every call that TAKES them. Every tool
  that answers about code takes them, with two exceptions: `smart_search`
  and `semantic_search` take neither, and they answer for the active
  build. An argument a tool does not declare is an error that names it.
- To learn whether a symbol is in the bootloader TOO, ask twice — once per
  image. Two plain answers beat one blended answer.

### Reading past the first page

Eight tools take an `offset` and lead with a page notice: `lookup_symbol`,
`search_code`, `search_bodies`, `search_content`, `find_callers`,
`find_references`, `find_dead_code`, `find_hotspots`.

    {"total": 137, "offset": 0, "shown": 50, "more": true, "hint": "…"}

It is ALWAYS there when the answer holds a row, thus a full page never
leaves you guessing whether more exists. `total` counts every row the
query matches; `more` says whether any are left.

Find the notice by its keys, and not by its position. A `warning` row
comes before it when the index is stale, and so does the row that reports
a query FTS5 could not parse.

- When `more` is true, call again with `offset=<offset + shown>`. The
  `hint` spells out that call.
- Do NOT conclude "that is all of them" from a page alone. Read `total` —
  a hot function can have hundreds of call sites, and a common name such
  as `read` can name hundreds of symbols.
- Each order is stable, thus two pages never overlap and never skip a
  row. The tools order by what they answer about: a reference by file and
  line, a symbol by definition first, a search by relevance and then by
  identity.
- An `info` row that names an offset means you walked past the end.

### Parameter names

Every tool rejects an unknown argument, thus a guess costs a whole call.
The schema of each tool is in the tool list — read it there. Three names
cover almost every tool:

- `name` — the symbol. NOT `symbol`, NOT `symbol_name`.
- `file_path` — the file (`read_file`, `get_file_map`).
- `query` — the search terms (every search tool).

No tool takes a filler argument. `get_active_build` accepts only
`project_root` and `fast`. When a call fails on an argument, drop that
argument and REPEAT the call — never continue without the answer, and
never skip `get_active_build`.

### search_bodies reaches more than functions

`search_bodies` searches the text of EVERY definition: a function or
method body, and also the body of a class, struct, union, enum or
namespace, and a global with a multi-line initializer. An enum constant,
a bit field, and a member declaration such as `InterruptIn _pin;` are all
inside it. A match on a type answers with the type, and `match_lines`
gives the line of the match itself.

Only the TEXT matches: a hit in the name, the signature or the
`llm_analysis` of a symbol is not a hit here — that is `search_code`.

Text that belongs to no definition is out of reach — `#define`,
`#include`, `#ifdef`, `extern "C"`, a file-scope comment. Use
`search_content` for those.

### search_content is the complement, not the fallback

The two answer different questions and reach different text:

- `search_bodies` — WHICH DEFINITION holds the pattern. Takes the query
  literally, thus it is the precise one.
- `search_content` — WHICH FILES the topic touches. Widens the query
  (see below), thus it reaches text the literal query misses. Measured:
  `SELF_TEST` gave 6 files here and 5 definitions through `search_bodies`,
  the extra file holding the comment `Self tester`.

For the footprint of one feature, run both.

### How each tool reads your query

- `search_code`, `search_content` — every bare term gets a trailing `*`
  and the terms are OR-joined: `modem init` → `modem* OR init*`, thus a
  symbol with EITHER word matches. Prefer single words.
- `search_bodies` — the query goes to FTS5 as you wrote it. A space is an
  AND of two exact tokens, and NO wildcard is added: `SELF_TEST` misses
  `Self tester`, and `SELF_TEST*` finds it. Add the `*` yourself.
- Every tool: punctuation is not searchable. FTS5 cannot parse `.attach(`,
  thus it is repaired into a phrase and what runs is the word `attach`.
  `search_bodies` marks such an answer (`_fallback: "sanitized"` +
  `_query_used`); the hits whose body really holds the pattern are the
  ones with `match_lines`.
- Every tool: an underscore separates words. `modem_init` asks for the two
  tokens next to each other and misses `modem_parser_oob_init`. Write
  `modem init` to reach it.
- An exact phrase is `'"interrupt handler"'` in every tool.

### Where a line number comes from

- `search_bodies`, `search_content` → `match_lines`, the lines of the
  matches. In `search_bodies`, `line` is the first line of the DEFINITION,
  far from the match in a long function. Never cite `line` for a statement.
- `get_source` / `get_file_map` → `line` and `end_line` are the extent.
  Cite `file:line-end_line`.
- `read_file` → pass `line_numbers=True`, or read a window with
  `start_line` / `end_line`. Never count the lines of a bare `content`.
- A field with NO leading underscore is an answer to cite. An `_`-prefixed
  field (`_match_snippet`, `_fallback`, `_source_truncated`) says where the
  answer came from.

These cover the statement-level anchor. Do not leave fw-context for a
text search to find a line number.

### Read the result you already have

Measured on one session: 4 of 12 calls asked again for something the
payload already carried.

1. Before you call anything for a `path:line`, re-read the last result.
   `match_lines` and `file` are usually already there.
2. Never repeat one query with a filter added. Write `kind` in the first
   call, or read `kind` on each result — the unfiltered answer already
   holds the filtered one.
3. Never invent a symbol name because "it should be called that".
   Take the name from a result. A guess costs a whole call.
4. A caller is `find_callers`, never a comment that reads like one.

### llm_analysis is not evidence

`llm_analysis` (`{summary, inputs, outputs}`) is written by a model, not
by the code. Use it to find a symbol. Never quote it as fact. Quote
`source`, `signature`, or `docstring`.

### Empty result playbook
An empty list means "no such code" — a query FTS5 cannot parse comes back
as a `warning` + `hint` instead, thus `[]` is an answer, not a failure.
1. Simplify to a single-word query in the same tool.
2. In `search_bodies`, add the `*` — the tool adds none.
3. Switch tools — search_bodies → search_content (wider query, and it
   covers the preprocessor and extern "C", which belong to no definition).
4. Use `lookup_symbol` for known names.
5. Only AFTER exhausting all fw-context tools — use other tools.

### A name that means several symbols

A common method name lives in many classes. `read`, `write`, `get` and
`size` each match dozens of symbols in a firmware project. A bare `probe`
names both `ClassA::probe` and `ClassB::probe`.

Every tool that takes a symbol name handles this, in one of two shapes.

**Tools that return ONE body** — `get_source`, `get_symbol_context`,
`explain_symbol` — answer for one symbol and add:

- `candidates` — a row per symbol that the name matched, with
  `qualified_name`, **`class`**, `kind`, `file`, `line` and `signature`.
  Pick from it and ask again with that `qualified_name`. Read `class`
  first: it is what tells two same-name methods apart.
- `candidates_total` — how many symbols the name matches ALTOGETHER.
  When it is larger than the list, `candidates` holds the most referenced
  ones; `lookup_symbol(name, exact=True)` lists them ALL and its `offset`
  pages through them. The two orders differ, so start that listing at the
  top — it is not a continuation of `candidates`.
- `ambiguous_warning` — one sentence that names the symbol the answer is
  about.

**Tools that return a LIST** — `find_all_callers_recursive`,
`find_callees_recursive`, `find_call_path`, `find_callers`,
`find_references` — answer for ALL of the symbols. The answer starts with
a `warning` row that names them, and each result carries
`target_qualified_name`, which tells the symbol it belongs to.

- Read `target_qualified_name` before you say who calls what. Without it
  a caller of one class reads as a caller of the other.
- An exact qualified name (`ClassB::probe`) always wins over a bare
  sibling, thus the answer then holds that symbol only.
- `lookup_symbol` lists every match with its `class`, and its `offset`
  parameter pages through a name that many classes share.

### Agent loop
Check(`get_active_build`) → Find(`search_code`/`lookup_symbol`)
→ Read(`get_symbol_context`) ← preferred. Fallback: `get_source` (body only).
→ Trace(`find_references`/`find_callers`) — skip if context from get_symbol_context.
→ For pattern-in-body searches use `search_bodies`.

get_active_build() status:
  • "ready" / "reindexing" — fully operational. Continue.
  • "reindex_needed" — queries work, schedule `fw-context index`.
  • "not_initialized" — ask operator, then run `fw-context init` via bash.
  • "no_index" — ask operator, then run `fw-context index --build` via bash.
  • "error" — DB corruption. Use other tools.

`client_restart_required: True` is not a status, and NO command repairs it.
The index holds a newer row format than this session reads, thus the index
is correct and this session is the old reader. Queries keep working. Do NOT
reindex — the indexer writes the same new format again and the field comes
back. Tell the operator to restart the LLM client (Claude Code, opencode,
or the client in use). The MCP server is a child process of that client,
thus nobody can restart the server alone. `client_restart_reason` holds the
wording.

### Diff verification

Diff shows only what changed — it cannot reveal impact across the full
codebase. After inspecting a diff, verify with fw-context:
  • `find_references("<symbol>")` — all callers/readers
  • `search_bodies("<pattern>")` — pattern consistency across codebase
  • `find_call_path` / `find_all_callers_recursive` — cross-module impact
  • `find_dead_code` / `find_hotspots` — structural effects

Do NOT use fw-context in Python, JS, Go, or other non-C/C++ projects.

### Tool categories

Search: lookup_symbol, search_code, search_bodies, search_content,
smart_search, semantic_search, explain_symbol.
Source: get_symbol_context, get_source, get_file_map, read_file.
Call graph: find_callers, find_references, find_call_path,
find_all_callers_recursive, find_callees_recursive, find_hotspots,
find_dead_code, find_wrapper_callers, trace_data_flow,
find_indirect_call_sites, find_indirect_targets.
Inheritance: get_inheritance_chain, get_class_members,
get_template_instances, get_method_overrides.
Maintenance: get_active_build, reindex_file, reset_index,
check_ollama, list_projects, get_project_info.

Individual tool descriptions are in the MCP tool listings —
discover them at runtime.


## SUBAGENT INSTRUCTIONS (applies to ALL subagents)

When you are launched as a subagent in a C/C++ project, the fw-context rules
above are MANDATORY for you — no exceptions, no excuses:

- NEVER read C/C++ source files (.c, .cpp, .h, .hpp, .s, .inc) with
  Read, cat, grep, or any non-fw-context tool.
- Raw source files contain unprocessed #ifdef noise — only fw-context shows
  what actually compiles for the active build configuration.
- If fw-context MCP tools are available, they are the ONLY allowed way to
  access C/C++ source code. No fallback to raw file reads.
- If you don't have fw-context tools available, state that limitation and
  stop — do NOT fall back to raw file reads.

The rules in the fw-context section above apply to you exactly as they apply
to the main session. There is no exemption for subagents.

<!-- /fw-context -->
