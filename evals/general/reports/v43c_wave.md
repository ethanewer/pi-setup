# v4.3c wave report — staging record

Wave: **v43c** (real-upstream-issue wave; 107 slots, 106 landed)
Staged by: `stage:v43c` workflow step, working branch `v4-eval`
Report timestamp: 2026-09-14T06:40:00Z; landed spec `specs/v43c_landed.json`
written earlier this pass (timestamp 2026-09-14T06:15:36Z)
Hand-off artifact: `specs/v43c_landed.json` — the review dossier verbatim plus
wave metadata (slot count, landed count, distinct repository count, difficulty
distribution, domain counts, timestamp). Registration is central and happens
once over all waves; this staging pass neither registered nor committed, and
left every shared spec (`coverage_claims.json`, `coverage.json`,
`difficulty.json`, `provenance.json`, `upstream_sources.json`, `WORKFLOW.md`)
untouched.

---

## 1. What this wave is

The v4.3 family mines **real upstream bug fixes** per
`reports/MINING_PROTOCOL_v43.md`: non-merge commits that change at least one
source file and one test file, mined from real repository histories, then
verified **both directions** in a container on the task's base image — the
reproduction fails at the pinned parent commit and passes at the fix commit,
with states moved only via `git reset --hard` (never the protocol's staging
trap `git checkout <sha> -- <path>`). The v4.3c wave adds one rule on top:
the instruction **does not hand the agent a reproduction or the fix
location** — the agent must write its own failing reproduction, localise the
defect, and fix it in a real tree. That rule is what pushes the difficulty
mix up.

Verified pool shared across the v4.3 family: **218 issues across 60 distinct
repositories** (`specs/v43_issue_pool/`, 60 pool files; 218/218 carry a
non-empty verified statement).

**v4.3c slots: 107. Landed: 106. Did not land: 1.** The 106 landed tasks span
**59 distinct repositories** — the largest wave of the suite so far.
## 2. What landed

| Task | Repository | Parent | Fix | Upstream ref | Difficulty |
|---|---|---|---|---|---|
| `alewife-anchorage` | BurntSushi/ripgrep | `bb88a1ac45` | `0407e104f6` | #3173 | medium |
| `alewife-dune` | Mbed-TLS/mbedtls | `d1615b814a` | `6bba0a8355` | #1247 (PR; upstream security advisory CVE-2024-45157… | medium |
| `barge-basin` | PyCQA/bandit | `ad56c78f1e` | `049eba08c9` | #1141 | medium |
| `berm-coaming` | duckdb/duckdb | `c54cb2c29b` | `cf77bda5a1` | #24616 | medium |
| `bitts-longshore` | sympy/sympy | `648f6cfb88` | `f1b4be1bf8` | 28744 | medium |
| `bollard-inlet` | syncthing/syncthing | `d4cffd848e` | `c1d8045d86` | #10785 | medium |
| `boom-ground` | tmux/tmux | `19a085a672` | `4714f478fe` | #5498 | medium |
| `bosun-fathom` | BurntSushi/ripgrep | `6244e635a1` | `4ab1862dc0` | BurntSushi/ripgrep#2944 | medium |
| `brackish-deepwater` | duckdb/duckdb | `916aeeb64b` | `17b972423b` | #25164 | hard |
| `bulwark-chartroom` | falconry/falcon | `1ae55f7d46` | `ce0a35b8fd` | #2667 (PR #2682) | medium |
| `capstan-cleat` | matplotlib/matplotlib | `7722dead68` | `e90952ffac` | #28386 (fix PR #28881) | medium |
| `caulk-ebb` | networkx/networkx | `1950928691` | `e9eac8a7e0` | issue #8726 | medium |
| `chain-companion` | nltk/nltk | `27b8ad6cd5` | `bd49f9011d` | #3694 (fix commit message: "allow escaped brackets i… | medium |
| `chandlery-waypoint` | PyCQA/flake8 | `446b18d35a` | `8b51ee4ea5` | #1642 | medium |
| `clew-bulkhead` | scipy/scipy | `4fe05c739b` | `d42bc45c3f` | scipy#26139 | medium |
| `cockboat-caboose` | psf/requests | `bc7dd0fc4d` | `f0198e6dfc` | https://github.com/psf/requests/issues/7309 | medium |
| `companion-berm` | python-poetry/poetry | `35eb5025dc` | `b8383e3cda` | #10805 | medium |
| `companion-flint` | python/mypy | `4e349a7c0b` | `d0b3fb3c89` | python/mypy#21431 | medium |
| `corvette-towpath` | Z3Prover/z3 | `e950cd371c` | `8d32b2b02a` | #10608 | medium |
| `crance-bell` | scipy/scipy | `d9b45feb89` | `6dbd21acb0` | #26026 | medium |
| `cringle-barquentine` | BurntSushi/ripgrep | `5e81c60b35` | `bc76a30c23` | #1891 | medium |
| `crojack-wheel` | sqlalchemy/sqlalchemy | `a49a4f021a` | `d466d37588` | #13176 | medium |
| `crosstrees-trough` | tmux/tmux | `936bb6e7cd` | `696a16cca2` | tmux GitHub issue 5511 (variation-selector-widened c… | medium |
| `cuddy-stem` | aio-libs/aiohttp | `14a1b54272` | `20acdf440b` | aio-libs/aiohttp#13536 | medium |
| `cutwater-swell` | BurntSushi/ripgrep | `6c5108ed17` | `9d738ad0c0` | #2884 | medium |
| `deadwood-shoal` | apache/commons-lang | `170e9f28ad` | `ae85262f04` | LANG-1828 (#1736) | medium |
| `dory-reach` | aquasecurity/trivy | `748a639b1d` | `0012281c8a` | #11050 | medium |
| `dragger-narrows` | astral-sh/uv | `dbbc4c9a1e` | `d28a3ee3d0` | astral-sh/uv #21529 (whitespace-padded .python-versi… | medium |
| `dunnage-light` | clap-rs/clap | `8bb3853eb5` | `3eacf5b8b0` | #3815 | medium |
| `fender-hull` | cure53/DOMPurify | `2c8ca25ef3` | `0332fe7cd4` | #1560 | medium |
| `figurehead-grapnel` | curl/curl | `81787b0b34` | `12cfc836c6` | #22868 | medium |
| `flotsam-fairway` | duckdb/duckdb | `e0b375a9a0` | `02f7eeb4db` | duckdb/duckdb#25166 | medium |
| `forecastle-current` | encode/httpx | `df5345140e` | `6d852d319a` | #3116 | medium |
| `gaff-boom` | explosion/spaCy | `453732d32d` | `cfa1d3a59a` | spaCy issue #13924 (fixed upstream at cfa1d3a59abd8e… | 13 (medium) |
| `gaff-gate` | expressjs/express | `ee40a881f5` | `723b5451bb` | #4212 | medium |
| `galiot-cinder` | falconry/falcon | `7191be4d19` | `69cdcd6edd` | falconry/falcon #2157, fixed by PR #2159 (commit 69c… | easy |
| `garboard-yard` | giampaolo/psutil | `1ae01d1210` | `73a2bfb915` | giampaolo/psutil#2793 (fixed by upstream PR #2818) | medium |
| `gasket-wake` | gin-gonic/gin | `fb2583442c` | `472d086af2` | #4535 | medium |
| `gunwale-tideway` | git/git (github.com/git/git) | `d9d677b2d8` | `c39952b925` | git-for-windows/git#4302 | medium |
| `halyard-spinnaker` | gohugoio/hugo | `8ee6de6d96` | `5758c370ea` | #7528 | medium |
| `hawse-shallows` | google/guava | `5367a2d068` | `55524c66de` | google/guava#1190 | medium |
| `hawser-quay` | jestjs/jest | `30b0642f7c` | `73f64cd2a2` | jestjs/jest PR #16338 "fix(jest-each): serialize big… | hard |
| `hoy-moor` | junit-team/junit5 | `f5b43ce4e8` | `1866c0c21b` | junit-team/junit5#5098 | medium |
| `jackstay-larboard` | librosa/librosa | `c7aa2ce80a` | `6ee6e4fc2d` | #2072 | medium |
| `jetsam-head` | libvips/libvips | `f0c38f9a7d` | `736059b2e8` | #5123 | medium |
| `jib-gangplank` | matplotlib/matplotlib | `2d87c95844` | `91740933b6` | The fix commit 91740933b658437016063f904030706d84b45… | medium |
| `kedge-fairway` | mikf/gallery-dl | `80a402f267` | `63b5745948` | mikf/gallery-dl#8661 | medium |
| `kelson-current` | netty/netty | `6dabf563b6` | `a655e648bf` | netty/netty#16951 | medium |
| `lazaret-careen` | networkx/networkx | `b1f9563440` | `304b3ae481` | #8755 | medium |
| `lighter-boom` | nltk/nltk | `c86229d218` | `1929bf9e36` | #1995/#3687 | medium |
| `lighter-gate` | pallets/click | `4271fe283d` | `d8763b9302` | #1489 | medium |
| `limber-cinder` | pallets/jinja | `1891320941` | `d5f49f5cc1` | pallets/jinja#1448 | medium |
| `luff-yard` | pallets/werkzeug | `795f4eaf6e` | `051fd66352` | #3127 | medium |
| `marlinespike-wake` | prettier/prettier | `ea8167fcca` | `8e05b371ab` | #19687 (not named anywhere in agent-visible files) | medium |
| `masthead-tideway` | prometheus/prometheus | `1885dfd99d` | `78169fb57d` | #19661 | hard |
| `midships-spinnaker` | psf/requests | `0b401c76b6` | `6404f345e5` | requests PR #7433 (Fix prepare_body stream detection… | medium |
| `mizzen-seaboard` | psycopg/psycopg | `19b58ffd05` | `793cd87863` | 1363 | medium |
| `mooring-port` | pylint-dev/pylint | `92b631fac2` | `5e00da601a` | #11357 | medium |
| `nock-meridian` | pypa/pip | `ba52753ecf` | `10dfb6b900` | #14110 | medium |
| `oakum-landfall` | pypa/setuptools | `d8da7dfaa0` | `9559193e1e` | #3777 (fixed via PR #4766, per v43_issue_pool slot e… | medium |
| `oarlock-haven` | pytest-dev/pytest | `efa117ad49` | `a88e91baca` | #14909 | medium |
| `outrigger-ferry` | python-poetry/poetry | `378c693f0e` | `35eb5025dc` | python-poetry/poetry#10804 | medium |
| `painter-ebb` | python/mypy | `cd75c4ec10` | `4c8f9944ea` | #21571 (also fixes #21106) | medium |
| `palliser-companion` | pytorch/vision | `8a5946ed6b` | `3cbf38e82f` | #9394 | Rubric total |
| `pennant-caboose` | redis/redis | `8f365337d4` | `4f20cb4893` | redis/redis#15489 | medium |
| `pintle-berm` | rust-lang/regex | `bbf0b38df6` | `73f7889021` | rust-lang/regex issue #1060 (referenced inside the g… | medium |
| `pintle-flint` | scikit-image/scikit-image | `9107d523a8` | `119a89bc10` | #7333 | medium |
| `plimsoll-bell` | scipy/scipy | `0f7f9b2a31` | `0f0a3dd37f` | #25448 | medium |
| `poop-wheel` | semgrep/semgrep | `ae531156ca` | `c7d2925fbe` | #9943 | medium |
| `portlight-trough` | serde-rs/serde | `c96efcb87a` | `873cfbe9ab` | serde-rs/serde #816 | medium |
| `quoin-swell` | sharkdp/fd | `7f1b1471d5` | `8dfa67a245` | sharkdp/fd#849 | medium |
| `ratline-sound` | spf13/cobra (V language, formerly 'Go') | `dbf85f6104` | `22b617914c` | #1776 (from slot entry specs/v43_issue_pool/spf13__c… | medium |
| `reef-sail` | sqlalchemy/sqlalchemy | `e51ff826b9` | `44be2ef448` | #11832 | medium |
| `ropewalk-passage` | starship/starship | `109a6811ce` | `2c11c086b8` | starship/starship#6861 (as labeled by the author; ve… | medium |
| `rudder-main` | statsmodels/statsmodels | `c67d83dc9b` | `3c7f8f8118` | #8190 | medium |
| `scantling-keel` | sympy/sympy | `08e73e6bd6` | `d696c93fbb` | #28970 | medium |
| `scupper-gulf` | syncthing/syncthing | `3ec73403c1` | `6be1ff8480` | syncthing/syncthing#10709 | medium |
| `sennit-foresheet` | tmux/tmux | `73db0a54e5` | `d44bfda26d` | #5576 | medium |
| `sheer-drift` | BurntSushi/ripgrep | `e6cac8b119` | `12dd455ee9` | ripgrep issue #1765 | medium |
| `sheet-coaming` | PyCQA/bandit | `6d6ec6d550` | `c420d1d535` | #764 | medium |
| `shroud-bulkhead` | aquasecurity/trivy | `a2777aed34` | `a10291be6f` | #10861 | medium |
| `sill-barquentine` | duckdb/duckdb | `b98263558b` | `115e593139` | duckdb issue #24602 (CREATE SEQUENCE NULL option cra… | medium |
| `sill-ember` | expressjs/express | `a1fa90fcea` | `a003cfab03` | #5554 #5555 | medium |
| `skiff-beacon` | falconry/falcon | `6566f4a425` | `7f55a5eb2e` | #2670 | medium |
| `spile-wharf` | giampaolo/psutil | `5ec16ad4d8` | `d46726028a` | #2809 (named by the upstream regression test's own c… | medium |
| `spindrift-trim` | gin-gonic/gin | `db309081bc` | `5c00df8afa` | gin-gonic/gin#4206 | medium |
| `stay-strait` | git/git | `6cd33dceed` | `d097a23bfa` | fix commit d097a23b (Its parent is exactly the pinne… | medium |
| `stem-sloop` | google/guava | `7731825df8` | `76260d9b3c` | Issue number not disclosed in the task materials by … | medium |
| `stern-roadstead` | jestjs/jest | `9ab14feccd` | `74bd550d15` | jestjs/jest#16345 | medium |
| `strake-offing` | matplotlib/matplotlib | `496ae85214` | `c72236701f` | #31182 | medium |
| `swivel-longshore` | networkx/networkx | `a7d049b499` | `73cb92bbae` | networkx/networkx #8879 (from task metadata; I verif… | medium |
| `tackle-inlet` | nltk/nltk | `47e236e950` | `5c4c0d3fe6` | nltk/nltk#3785 | medium |
| `thole-ground` | pallets/werkzeug | `b97e13cc74` | `f88164a271` | float route converter emits scientific notation for … | medium |
| `tiller-fathom` | prettier/prettier | `c03ab4e71c` | `dd5e24eabe` | #19621 | medium |
| `topsail-deepwater` | prometheus/prometheus | `6f81b2271a` | `94ddb36f64` | #18051 | medium |
| `transom-chartroom` | psf/requests | `4443b1a847` | `bc7dd0fc4d` | #7308 | medium |
| `trawler-bowsprit` | pypa/setuptools | `92b45e9817` | `df45427cbb` | pypa/setuptools#4302 | medium |
| `trawler-grove` | python-poetry/poetry | `b8383e3cda` | `3f7feee698` | real upstream issue #10809 (per author notes), fixed… | medium |
| `tumblehome-crest` | python/mypy | `0007c52672` | `b7a8bab4e5` | #21409 (issue) / #21411 (fix PR) | medium |
| `wale-beacon` | pytorch/vision | `c7ef957c29` | `50237caaf6` | #9615 | medium |
| `waterway-wharf` | rust-lang/regex | `c5e9de9d6e` | `f15f3dcbc3` | #1046 | medium |
| `wherry-trim` | scikit-image/scikit-image | `f1892afb76` | `137dbfb5f1` | #7496 | medium |
| `windward-strait` | scipy/scipy | `a804efa6ec` | `34d57a75ac` | scipy/scipy#26044 | hard |
| `yard-sloop` | semgrep/semgrep | `e3f9cc5098` | `d7a3e3bd43` | semgrep/semgrep#10184 | medium |
| `yaw-roadstead` | github.com/spf13/cobra | `6bf8cd8582` | `7790bf97fd` | spf13/cobra#1771 | medium |
| `yawl-offing` | sqlalchemy/sqlalchemy | `16177b8c73` | `bd0da42630` | #13439 | medium |

*Parent/fix shown as the first 10 hex chars. Difficulty is `task.toml
[metadata].difficulty`, re-read by this staging pass; the difficulty.json
rubric bucket agrees with task.toml for all 106 tasks (0 mismatches).*

**Difficulty distribution of what landed: 1 easy / 101 medium / 4 hard.**
Rubric totals of the 106: 8 (easy — `galiot-cinder`), 11 (×14), 12 (×33),
13 (×30), 14 (×11), 15 (×8), 16 (×3), 17 (×2), 18 (hard — ×4:
`brackish-deepwater`, `hawser-quay`, `masthead-tideway`, `windward-strait`).
The operator accepted a changed difficulty mix in exchange for more
high-quality, diverse tasks; the mix is reported here as measured, not
defended.

## 3. How reviewers confirmed each issue is real and the fix unreachable

All 106 dossiers carry an independent `issue_confirmed_by_reviewer`
confirmation, produced by a uniform per-task method:

* fresh containers on the task's clone / base image; states moved only with
  `git reset --hard` (+ `git clean -fd`) or fresh clones at the fix SHA;
* the buggy code proven present by inspection at the parent (line numbers
  quoted), and the fixed form at the fix commit;
* the upstream regression test re-extracted from the fix commit
  (`git show <fix>:<path>`), sha256-compared against the
  Dockerfile/verifier pins;
* the author's reproduction failing at parent with the exact mined output and
  exit code, and passing at fix;
* the project's own suites run on both states; every authored hidden case
  verified failing at parent / passing at fix.

Representative confirmations (full detail in the dossier): corvette-towpath —
the pinned fp.fma binary16 query prints `sat` at parent and `unsat` after the
one-line fix, and the upstream regression block aborts with an ASSERTION
VIOLATION at parent; pennant-caboose — `XINFO GROUPS` reports entries-read 10 /
lag -8 and `DEBUG RELOAD` fails ("ERR Error trying to load the RDB dump") at
parent, entries-read 2 / lag 0 after the fix; alewife-dune — the 544-bit
ECDSA case aborts the mbedtls suite with `*** buffer overflow detected ***`
(rc 134) at parent and the fix commit's 43-case suite passes 43/43.

**Fix object unreachable inside the shipped image: 106/106, proven by this
staging pass.** For each of the 106 accepted tasks the environment image was
built from the shipped `environment/Dockerfile` and, inside a container, the
check ran `git -C <working-clone> cat-file -e <fix>^{commit}` over every git
worktree found under /app, /opt, /root and /home (typically 2 per image — the
agent clone under /app/src plus a pristine /opt/prefix or /opt/pretree
snapshot). **The fix commit object is absent from every one of the 106
images** (rc 128, "Not a valid object name"), and the agent clone sits at the
pinned parent (single-commit object store for the corrected recipes). The
check recorded zero failures (script `/tmp/v43creach`, 6 workers, images
removed after each check). Several reviewers found and closed *additional*
reachability channels the author had declared unreachable (default-branch tip
in the pack, leftover fix clones under /tmp, world-readable golden files —
section 4); on the final tree, object-absence is universal.| Task | Repository | Parent | Fix | Upstream ref | Difficulty |
|---|---|---|---|---|---|
| `alewife-anchorage` | BurntSushi/ripgrep | `bb88a1ac45` | `0407e104f6` | #3173 | medium |
| `alewife-dune` | Mbed-TLS/mbedtls | `d1615b814a` | `6bba0a8355` | #1247 | medium |
| `barge-basin` | PyCQA/bandit | `ad56c78f1e` | `049eba08c9` | #1141 | medium |
| `berm-coaming` | duckdb/duckdb | `c54cb2c29b` | `cf77bda5a1` | #24616 | medium |
| `bitts-longshore` | sympy/sympy | `648f6cfb88` | `f1b4be1bf8` | 28744 | medium |
| `bollard-inlet` | syncthing/syncthing | `d4cffd848e` | `c1d8045d86` | #10785 | medium |
| `boom-ground` | tmux/tmux | `19a085a672` | `4714f478fe` | #5498 | medium |
| `bosun-fathom` | BurntSushi/ripgrep | `6244e635a1` | `4ab1862dc0` | BurntSushi/ripgrep#2944 | medium |
| `brackish-deepwater` | duckdb/duckdb | `916aeeb64b` | `17b972423b` | #25164 | hard |
| `bulwark-chartroom` | falconry/falcon | `1ae55f7d46` | `ce0a35b8fd` | #2667 | medium |
| `capstan-cleat` | matplotlib/matplotlib | `7722dead68` | `e90952ffac` | #28386 | medium |
| `caulk-ebb` | networkx/networkx | `1950928691` | `e9eac8a7e0` | issue #8726 | medium |
| `chain-companion` | nltk/nltk | `27b8ad6cd5` | `bd49f9011d` | #3694 | medium |
| `chandlery-waypoint` | PyCQA/flake8 | `446b18d35a` | `8b51ee4ea5` | #1642 | medium |
| `clew-bulkhead` | scipy/scipy | `4fe05c739b` | `d42bc45c3f` | scipy#26139 | medium |
| `cockboat-caboose` | psf/requests | `bc7dd0fc4d` | `f0198e6dfc` | https://github.com/psf/requests/issues/7309 | medium |
| `companion-berm` | python-poetry/poetry | `35eb5025dc` | `b8383e3cda` | #10805 | medium |
| `companion-flint` | python/mypy | `4e349a7c0b` | `d0b3fb3c89` | python/mypy#21431 | medium |
| `corvette-towpath` | Z3Prover/z3 | `e950cd371c` | `8d32b2b02a` | #10608 | medium |
| `crance-bell` | scipy/scipy | `d9b45feb89` | `6dbd21acb0` | #26026 | medium |
| `cringle-barquentine` | BurntSushi/ripgrep | `5e81c60b35` | `bc76a30c23` | #1891 | medium |
| `crojack-wheel` | sqlalchemy/sqlalchemy | `a49a4f021a` | `d466d37588` | #13176 | medium |
| `crosstrees-trough` | tmux/tmux | `936bb6e7cd` | `696a16cca2` | tmux GitHub issue 5511 | medium |
| `cuddy-stem` | aio-libs/aiohttp | `14a1b54272` | `20acdf440b` | aio-libs/aiohttp#13536 | medium |
| `cutwater-swell` | BurntSushi/ripgrep | `6c5108ed17` | `9d738ad0c0` | #2884 | medium |
| `deadwood-shoal` | apache/commons-lang | `170e9f28ad` | `ae85262f04` | LANG-1828 | medium |
| `dory-reach` | aquasecurity/trivy | `748a639b1d` | `0012281c8a` | #11050 | medium |
| `dragger-narrows` | astral-sh/uv | `dbbc4c9a1e` | `d28a3ee3d0` | astral-sh/uv #21529 | medium |
| `dunnage-light` | clap-rs/clap | `8bb3853eb5` | `3eacf5b8b0` | #3815 | medium |
| `fender-hull` | cure53/DOMPurify | `2c8ca25ef3` | `0332fe7cd4` | #1560 | medium |
| `figurehead-grapnel` | curl/curl | `81787b0b34` | `12cfc836c6` | #22868 | medium |
| `flotsam-fairway` | duckdb/duckdb | `e0b375a9a0` | `02f7eeb4db` | duckdb/duckdb#25166 | medium |
| `forecastle-current` | encode/httpx | `df5345140e` | `6d852d319a` | #3116 | medium |
| `gaff-boom` | explosion/spaCy | `453732d32d` | `cfa1d3a59a` | spaCy issue #13924 | 13 |
| `gaff-gate` | expressjs/express | `ee40a881f5` | `723b5451bb` | #4212 | medium |
| `galiot-cinder` | falconry/falcon | `7191be4d19` | `69cdcd6edd` | falconry/falcon #2157, fixed by PR #2159 | easy |
| `garboard-yard` | giampaolo/psutil | `1ae01d1210` | `73a2bfb915` | giampaolo/psutil#2793 | medium |
| `gasket-wake` | gin-gonic/gin | `fb2583442c` | `472d086af2` | #4535 | medium |
| `gunwale-tideway` | git/git (github.com/git/git) | `d9d677b2d8` | `c39952b925` | git-for-windows/git#4302 | medium |
| `halyard-spinnaker` | gohugoio/hugo | `8ee6de6d96` | `5758c370ea` | #7528 | medium |
| `hawse-shallows` | google/guava | `5367a2d068` | `55524c66de` | google/guava#1190 | medium |
| `hawser-quay` | jestjs/jest | `30b0642f7c` | `73f64cd2a2` | jestjs/jest PR #16338 "fix | hard, |
| `hoy-moor` | junit-team/junit5 | `f5b43ce4e8` | `1866c0c21b` | junit-team/junit5#5098 | medium |
| `jackstay-larboard` | librosa/librosa | `c7aa2ce80a` | `6ee6e4fc2d` | #2072 | medium |
| `jetsam-head` | libvips/libvips | `f0c38f9a7d` | `736059b2e8` | #5123 | medium |
| `jib-gangplank` | matplotlib/matplotlib | `2d87c95844` | `91740933b6` | The fix commit 91740933b658437016063f904030706d84b4502b adds | medium |
| `kedge-fairway` | mikf/gallery-dl | `80a402f267` | `63b5745948` | mikf/gallery-dl#8661 | medium |
| `kelson-current` | netty/netty | `6dabf563b6` | `a655e648bf` | netty/netty#16951 | medium |
| `lazaret-careen` | networkx/networkx | `b1f9563440` | `304b3ae481` | #8755 | medium |
| `lighter-boom` | nltk/nltk | `c86229d218` | `1929bf9e36` | #1995/#3687 | medium |
| `lighter-gate` | pallets/click | `4271fe283d` | `d8763b9302` | #1489 | medium |
| `limber-cinder` | pallets/jinja | `1891320941` | `d5f49f5cc1` | pallets/jinja#1448 | medium |
| `luff-yard` | pallets/werkzeug | `795f4eaf6e` | `051fd66352` | #3127 | medium |
| `marlinespike-wake` | prettier/prettier | `ea8167fcca` | `8e05b371ab` | #19687 | medium |
| `masthead-tideway` | prometheus/prometheus | `1885dfd99d` | `78169fb57d` | #19661 | hard |
| `midships-spinnaker` | psf/requests | `0b401c76b6` | `6404f345e5` | requests PR #7433 | medium |
| `mizzen-seaboard` | psycopg/psycopg | `19b58ffd05` | `793cd87863` | 1363 | medium |
| `mooring-port` | pylint-dev/pylint | `92b631fac2` | `5e00da601a` | #11357 | medium |
| `nock-meridian` | pypa/pip | `ba52753ecf` | `10dfb6b900` | #14110 | medium |
| `oakum-landfall` | pypa/setuptools | `d8da7dfaa0` | `9559193e1e` | #3777 | medium |
| `oarlock-haven` | pytest-dev/pytest | `efa117ad49` | `a88e91baca` | #14909 | medium |
| `outrigger-ferry` | python-poetry/poetry | `378c693f0e` | `35eb5025dc` | python-poetry/poetry#10804 | medium |
| `painter-ebb` | python/mypy | `cd75c4ec10` | `4c8f9944ea` | #21571 | medium |
| `palliser-companion` | pytorch/vision | `8a5946ed6b` | `3cbf38e82f` | #9394 | Rubric |
| `pennant-caboose` | redis/redis | `8f365337d4` | `4f20cb4893` | redis/redis#15489 | medium |
| `pintle-berm` | rust-lang/regex | `bbf0b38df6` | `73f7889021` | rust-lang/regex issue #1060 | medium |
| `pintle-flint` | scikit-image/scikit-image | `9107d523a8` | `119a89bc10` | #7333 | medium |
| `plimsoll-bell` | scipy/scipy | `0f7f9b2a31` | `0f0a3dd37f` | #25448 | medium |
| `poop-wheel` | semgrep/semgrep | `ae531156ca` | `c7d2925fbe` | #9943 | medium |
| `portlight-trough` | serde-rs/serde | `c96efcb87a` | `873cfbe9ab` | serde-rs/serde #816 | medium |
| `quoin-swell` | sharkdp/fd | `7f1b1471d5` | `8dfa67a245` | sharkdp/fd#849 | medium |
| `ratline-sound` | spf13/cobra (V language, formerly 'Go') | `dbf85f6104` | `22b617914c` | #1776 | medium |
| `reef-sail` | sqlalchemy/sqlalchemy | `e51ff826b9` | `44be2ef448` | #11832 | medium |
| `ropewalk-passage` | starship/starship | `109a6811ce` | `2c11c086b8` | starship/starship#6861 | medium |
| `rudder-main` | statsmodels/statsmodels | `c67d83dc9b` | `3c7f8f8118` | #8190 | medium |
| `scantling-keel` | sympy/sympy | `08e73e6bd6` | `d696c93fbb` | #28970 | medium |
| `scupper-gulf` | syncthing/syncthing | `3ec73403c1` | `6be1ff8480` | syncthing/syncthing#10709 | medium |
| `sennit-foresheet` | tmux/tmux | `73db0a54e5` | `d44bfda26d` | #5576 | medium |
| `sheer-drift` | BurntSushi/ripgrep | `e6cac8b119` | `12dd455ee9` | ripgrep issue #1765 | medium |
| `sheet-coaming` | PyCQA/bandit | `6d6ec6d550` | `c420d1d535` | #764 | medium |
| `shroud-bulkhead` | aquasecurity/trivy | `a2777aed34` | `a10291be6f` | #10861 | medium |
| `sill-barquentine` | duckdb/duckdb | `b98263558b` | `115e593139` | duckdb issue #24602 | medium |
| `sill-ember` | expressjs/express | `a1fa90fcea` | `a003cfab03` | #5554 #5555 | medium |
| `skiff-beacon` | falconry/falcon | `6566f4a425` | `7f55a5eb2e` | #2670 | medium |
| `spile-wharf` | giampaolo/psutil | `5ec16ad4d8` | `d46726028a` | #2809 | medium |
| `spindrift-trim` | gin-gonic/gin | `db309081bc` | `5c00df8afa` | gin-gonic/gin#4206 | medium |
| `stay-strait` | git/git | `6cd33dceed` | `d097a23bfa` | fix commit d097a23b | medium |
| `stem-sloop` | google/guava | `7731825df8` | `76260d9b3c` | Issue number not disclosed in the task materials by design | medium |
| `stern-roadstead` | jestjs/jest | `9ab14feccd` | `74bd550d15` | jestjs/jest#16345 | medium |
| `strake-offing` | matplotlib/matplotlib | `496ae85214` | `c72236701f` | #31182 | medium |
| `swivel-longshore` | networkx/networkx | `a7d049b499` | `73cb92bbae` | networkx/networkx #8879 | medium |
| `tackle-inlet` | nltk/nltk | `47e236e950` | `5c4c0d3fe6` | nltk/nltk#3785 | medium |
| `thole-ground` | pallets/werkzeug | `b97e13cc74` | `f88164a271` | float route converter emits scientific notation for extreme  | 16 |
| `tiller-fathom` | prettier/prettier | `c03ab4e71c` | `dd5e24eabe` | #19621 | medium |
| `topsail-deepwater` | prometheus/prometheus | `6f81b2271a` | `94ddb36f64` | #18051 | medium |
| `transom-chartroom` | psf/requests | `4443b1a847` | `bc7dd0fc4d` | #7308 | medium |
| `trawler-bowsprit` | pypa/setuptools | `92b45e9817` | `df45427cbb` | pypa/setuptools#4302 | medium |
| `trawler-grove` | python-poetry/poetry | `b8383e3cda` | `3f7feee698` | real upstream issue #10809 | medium |
| `tumblehome-crest` | python/mypy | `0007c52672` | `b7a8bab4e5` | #21409 | medium |
| `wale-beacon` | pytorch/vision | `c7ef957c29` | `50237caaf6` | #9615 | medium |
| `waterway-wharf` | rust-lang/regex | `c5e9de9d6e` | `f15f3dcbc3` | #1046 | medium |
| `wherry-trim` | scikit-image/scikit-image | `f1892afb76` | `137dbfb5f1` | #7496 | medium |
| `windward-strait` | scipy/scipy | `a804efa6ec` | `34d57a75ac` | scipy/scipy#26044 | hard |
| `yard-sloop` | semgrep/semgrep | `e3f9cc5098` | `d7a3e3bd43` | semgrep/semgrep#10184 | medium |
| `yaw-roadstead` | github.com/spf13/cobra | `6bf8cd8582` | `7790bf97fd` | spf13/cobra#1771 | medium |
| `yawl-offing` | sqlalchemy/sqlalchemy | `16177b8c73` | `bd0da42630` | #13439 | medium |

## 4. Bypasses reviewers found and closed

Reviewers attacked each verifier in the role of the trial user (root agent,
some /tests mounts writable, egress unless declared — see section 6). For
**94 of 106** tasks the dossier reports a concrete gap/leak closed by the
reviewer; **11** reviewers probed and found no escapable gap
(`alewife-anchorage`, `barge-basin`, `gaff-boom`, `kelson-current`,
`scantling-keel`, `skiff-beacon`, `spile-wharf`, `tackle-inlet`,
`topsail-deepwater`, `wale-beacon`, `wherry-trim`); one (`hoy-moor`) reports a verified-closed estate. The families (each with at least one demonstrated
exploit that was closed before acceptance):

* **Interpreter/site-shim seams** — root agent plants `sitecustomize.py` /
  `usercustomize.py` / `.pth` re-points / sys.modules rebinds that apply the
  fix at import time: demonstrated reward 1 before closure on e.g.
  `luff-yard`, `limber-cinder`, `swivel-longshore`, `oakum-landfall`,
  `mizzen-seaboard`, `jib-gangplank`, `plimsoll-bell`; closed with `-S`
  everywhere, `PYTHONNOUSERSITE=1`, site-packages manifests and
  interpreter/hook scans.
* **Toolchain/binary substitution** — fake `go`/`cargo`/`maven`/`mocha`/
  `python` executables, `.bin` symlink re-points, planted binaries in
  `target/`: closed with sha256 pins of the tools, ELF-header checks, plus a
  **forced rebuild from the current tree** (graded binary deleted, `make
  clean` / `cargo clean` / `git clean -fdx` and relink under the verifier),
  so the graded artifact provably derives from the delivered sources.
* **Compile-stage smuggling** — gitignored `.o`/`.so`/class artifacts and
  prebuilt binaries with backdated mtimes, compiler-wrapper `config.mak`
  under `autom4te.cache`, lying test harnesses in `target/debug/deps`:
  demonstrated on `dunnage-light` (fake builder binary), `alewife-dune`
  (planted `.o` + lib), `sennit-foresheet` (stale `.o`), `stay-strait`
  (compile wrapper); closed by tree purges and from-source rebuilds.
* **Git-index deception** — `git update-index --assume-unchanged` /
  `skip-worktree`, `git rm --cached` + `.git/info/exclude`, `git replace`
  graft/forgery: closed with per-file worktree-byte hashing against pinned
  parent blobs, `git ls-files -v` scans, index-vs-`git ls-tree $PARENT`
  equality, and `GIT_NO_REPLACE_OBJECTS`.
* **Golden/verifier/reward tampering** — root agent overwrites `/opt/golden`,
  plants conftest/`/tests`-dir injection after the agent phase, deletes
  hidden-check scripts, pre-planted `/logs/verifier/reward.txt=1` or a
  kill-mid-run replay: closed by literal sha256 pins of the golden bytes and
  of the whole `/tests` tree, `rm`+`echo 0` of the reward file at verifier
  start, fail paths writing 0, root-owned read-only pins.
* **Output hardcoding / input enumeration** — per-input special cases on
  verifier-visible inputs, fixed-answer reproductions, dead-code strings:
  closed with hidden cases that genuinely differ from the golden and, where
  needed, **runtime-generated random inputs** (no shipped file enumerates
  them): `jib-gangplank`, `outrigger-ferry`, `portlight-trough`, `caulk-ebb`,
  `swivel-longshore`; plus both-directions reproductions and pristine-tree
  fail controls.
* **Reproduction-path bias** — cwd/PATH/env-keyed fake reproductions or
  goldens that carry the failing input: closed by running both reproduction
  legs in identical sandboxes (same cwd, same PATH) differing only in file
  content, materialising the pristine tree via `git archive`, moving golden
  bytes to the verifier-only `/tests` mount (e.g. `crance-bell` — golden moved out of the image altogether), and requiring
  the reproduced numbers to equal the real library's.
* **The answer-bytes-are-in-the-image family** — a fix that is object-absent
  yet *content*-reachable:
  * the side effect of `git clone --depth 1` fetching the default-branch tip whose
    tree contains the fix (readable via `git show origin/main:...` with no
    network): found and closed in `deadwood-shoal`, `poop-wheel`,
    `lighter-gate`, `forecastle-current`, `bulwark-chartroom` (the last
    also shipped a bare fix-clone at `/tmp/fixsrc` plus the full upstream
    test file); the recipe is now `git init` + one depth-1 fetch of the
    parent with fail-closed ref/count asserts;
  * throwaway-clone leftovers and build logs carrying golden/fix bytes
    (mypy's cache DB stamped the fix SHA in `pintle-berm`/`companion-flint`,
    `fender-hull`'s /tmp transcript): scrubbed at build and re-asserted;
  * golden tests that embed the reproduction living world-readable in the
    image: `pintle-berm` (chmod 400 + report-name gate),
    `crance-bell` (moved to verifier-only /tests), `sheet-coaming` (fix
    bytes removed from the image entirely).

No demonstrated reward-1 cheat on an untouched tree reached acceptance: every
fix was proven to bite (attack → 0) and the honest oracle to still score 1,
per `tools/verify_new_task.sh` re-runs by each reviewer; this staging pass
re-ran the whole census independently (section 7).
## 5. What did not land, and why

`did_not_land.author_did_not_achieve` (1), `author_returned_null` (0),
`dropped_by_reviewer` (0):

* **futtock-careen (eslint/eslint)** — the author completed the mandated
  reading (authoring specs + slot + the v42 section‑9 egress finding), the
  throwaway build-timing probe (~4 min at 1 CPU, feasible), and a both-
  directions confirmation of the bug in a scratch image, and had a firm plan
  matching the house pattern of the accepted bracket-family tasks — but the
  harness cut the turn off before any task artefact was written. There is no
  `tasks/futtock-careen/` directory (no task.toml, instruction,
  difficulty, Dockerfile, solution, tests), and neither acceptance gate was
  run. Recorded honestly as abandoned; registration must treat it as a
  non-landed slot.

## 6. Instruction-leak check (network-egress-aware)

Per task, `instruction.md` was grepped against the slot entry for: (1) the
upstream issue number(s), (2) the PR number(s), (3) the fix commit (full and
short), (4) the basename(s) of the source files the fix touched, and (5)
runnable reproduction literals (commands / concrete inputs / exact outputs
from the slot's `reproduction` and `observed_failure_at_parent`).

**Results: 0 of 106 instructions leak an issue number, a PR number, or the
fix commit.** 36 instruction files raised literal flags; each resolves to an
allowed class — the quoted token is a user-visible symptom (engine/linter
error text, warning string, panic message), the basename is a **test module**
the spec mandates naming for the "run the project's own suite" command
(`test_*.py`, `test_*.go`, `testing/…` — not the fix source file as a
named change target, e.g. `jib-gangplank` cites `test_axes.py`, never
`axes/_axes.py`), or it is a diagnostic/import path. The positive-total
leaks found by reviewers *during* the wave (instruction or README rewrites in
`dragger-narrows`, `sheer-drift`, `bosun-fathom`, `brackish-deepwater`,
`lazaret-careen`, `companion-berm`, `lighter-gate`, `chain-companion`,
`limber-cinder`, `scantling-keel`, `ropewalk-passage`, `cringle-barquentine`,
`clew-bulkhead`, `hawse-shallows`/`strake-offing` README-BUILD,
`hawser-quay`, `forecastle-current`) were each closed with a re-run of
`tools/verify_new_task.sh` to PASS. This staging pass found no further
edit needed.

Egress: 22 tasks now declare `network_mode = "no-network"` in task.toml
(both agent+verifier; some also environment). Reviewers measured live egress
in trial containers with default policy PUBLIC and closed it exactly there
(e.g. `jackstay-larboard`, `mizzen-seaboard`, `lazaret-careen` added network
declarations; for the fix, the object is absent and no identifier is leaked,
so nothing remains to be fetched even with egress).
## 7. Both-directions census (this staging pass)

Two census invocations of `runs/census-v43c.sh`, each running
`tools/verify_new_task.sh` per task (static gates attributed per task,
`check_binary_reward.py`, then harbor **oracle** and harbor **nop**):

1. the main census (`/tmp/v43c-census`, 8 shards) measured **102** of the 106
   tasks; the 4 remaining tasks (`companion-berm`, `companion-flint`,
   `crance-bell`, `crojack-wheel`) were under review then and were **excluded
   by design**, and 2 (`berm-coaming`, `cringle-barquentine`) were queued while
   under review and therefore flagged for re-measurement;
2. a final, fresh census (`/tmp/v43c-census-final`, 3 shards, `RESUME=0`) over
   exactly those 6 — `companion-berm`, `companion-flint`, `crance-bell`,
   `crojack-wheel`, `berm-coaming`, `cringle-barquentine` — producing
   the authoritative result for all six.

**Tally, parsed from the raw per-task run lines — `oracle: harbor_rc=0
reward=…` and `nop: harbor_rc=0 reward=…` — not from any summary line:
106 of 106 tasks earned oracle reward `1` and nop reward `0`, with
`harbor_rc=0` on all 212 runs.** (Every part of that sentence is read from
the per-task logs; a per-task reward file `verifier/reward.txt` under each
run was the source the gate printed.) Reward records per task:
`/tmp/v43c-census-final` (the 6) and `/tmp/v43c-census/*.log` + the
consolidated `/tmp/v43c-census-tally.json` written this pass (106 rows:
task, oracle rc+reward, nop rc+reward, gate rc).

Suite-wide static gates on the census runs: lint rc=0 (one note names
`zephyr-forge`, an other-wave slot — filtered, none of the 106 named),
guard rc=0 (1075 guarded, 0 to patch), threads rc=0 (200 pinned), gitsafe rc=0 (248
safe), pippins rc=0, difficulty rc=0 (699 measured, problems=0, buckets
easy 107 / medium 337 / hard 255).

**Zero tasks slipped this census.** (Earlier waves of this family caught
several tasks that had passed both author and reviewer; this wave's census,
run with the same raw-log method, found none.)

## 8. Fix-unreachability over every built image — measured this pass

Step 3 of the staging brief: for each accepted task, **build the image and
prove the fix commit is unreachable inside the agent's working clone**.
Method and result are in section 3: 106 images built (6 workers; images
removed after each check), and `git cat-file -e <fix>^{commit}` **failed in
every agent-side clone** (rc 128), with the tree at the pinned parent.
No task failed the check; the full per-task list of worktrees checked is in
`/tmp/v43creach/`.

## 9. Upstream-clone disjointness from Terminal-Bench 2.1

`python3 tools/check_upstream_disjointness.py` (no `--apply`):

```
tasks_cloning_upstream=238 distinct_repositories=79 forbidden_list=68 problems=0 warnings=0
exit 0
```

**The intersection of this wave's 59 repositories with the 68-repository TB2.1
forbidden list is zero** — confirmed suite-wide (0 problems/0 warnings) and
independently per-wave on both raw and `github.com/owner/repo`-normalized
names (`specs/tb21_source_repositories.json`). The `--apply` write to
`specs/upstream_sources.json` was not run; that spec is owned by the
coordinating wave.

## 10. What the wave added — diversity, measured

* Distinct repositories added: **59** (v43b: 32; v4.3: 30).
* Difficulty vs the previous wave's 28 easy / 22 medium / 0 hard:
  **1 easy / 101 medium / 4 hard** (section 2). Operator accepted the mix
  change; reported as measured.
* Domains (assigned per repository following the v43b family scheme, adding
  the `python-web` family for the HTTP/web libraries this wave carries):

| domain | tasks | domain | tasks |
|---|---|---|---|
| scientific-python | 13 | js-tooling | 6 |
| python-web (new) | 13 | jvm-systems | 5 |
| data-engine | 11 | computer-vision | 5 |
| rust-cli | 9 | nlp | 4 |
| systems-c | 9 | theorem-proving-or-solvers | 1 |
| program-analysis | 8 | speech-audio | 1 |
| security-tooling | 7 | — | — |
| packaging-release | 7 | go-infrastructure | 7 |

(sums to 106 tasks across 15 domains; per-task assignments listed in
`specs/v43c_landed.json` and the dossier.) Some repositories appear
several times in the wave (ripgrep ×7, requests ×3, duckdb ×3, networkx
×4…): the pool deliberately spaces multiple independent issues per repo.

## 11. Directory census (registration prerequisite)

For all 106 tasks: `task.toml`, `instruction.md`, `difficulty.json`,
`environment/Dockerfile`, executable `solution/solve.sh`, `tests/test.sh`,
non-empty `tests/hidden/` — 106/106. All `task.toml` files parse;
difficulty.json rubric buckets match task.toml difficulty (0 mismatches).
(`tests/test.sh` is invoked by harbor as `bash -c /tests/test.sh`, so the
exec bit is not a requirement; all `solution/solve.sh` are executable.)

**No upstream source or test file is committed under any task directory:
106/106.** The walk searched every task tree for the slot entry's
`source_files_changed` / golden-test basenames and for top-level vendored
repository manifests (Cargo.toml / pyproject.toml / go.mod / package.json /
pom.xml at tree roots with upstream structure). The only basename collisions
are the two intended exceptions that live outside the agent-visible
deliverable: the golden test under the verifier-only `tests/golden/` mount
(`dunnage-light`) and the oracle's reference patched files under
`solution/` (`shroud-bulkhead`), which harbor mounts only for oracle runs.

## 12. What is deliberately NOT done: the contamination audit

**No contamination audit was run, and no audit verdict is claimed.** The tree
is not frozen: other v4.3x waves are still authoring into the same `tasks/`
tree (in-flight directories appear in every suite-wide gate), and this
wave's directories are not committed (registration commits them later, over
both waves). An audit over a moving tree is not a snapshot — the suite has
been burned by that mistake before, and the operator's plan states the
authoritative audit runs once, after the wave completes, at consolidated
registration. The byte-level n-gram audit
(`tools/audit_independence_stream.py`) therefore runs there, not here.

Things that cannot be deferred and were done here: image-level
fix-unreachability (106/106, §3/§8), instruction-leak hygiene (0/106,
§6), directory completeness and no-vendoring (§11), upstream-clone
disjointness (zero, §9), and the both-directions census (106/106 PASS,
§7).

Nothing was published (no harbor agent sweep beyond the oracle/nop census
runs; no model scores; no leaderboard/HF export), no git
add/commit/checkout/branch was run, no shared spec was edited, and `--apply`
was not run on the disjointness tool.

— end of the v4.3c wave staging report —
