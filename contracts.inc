===============================================================================
WireGuard Control Plane — Global Contracts
===============================================================================

This file defines all non-negotiable invariants for the WireGuard control plane.

It is documentation-as-law.
It contains no executable logic.
It MUST be kept in Git and reviewed like code.

All compiler, renderer, checker, and deployment scripts MUST comply with
these contracts.


-------------------------------------------------------------------------------
CONTRACT: Contract authority & precedence
-------------------------------------------------------------------------------

Contracts are the source of truth.

Rules:

  - Contracts may only change via an explicit Git commit
  - Implementations MUST follow contracts; contracts MUST NOT be altered
    to accommodate existing implementations
  - If an implementation conflicts with a contract, the implementation
    MUST be corrected or removed
  - Contract amendments MUST be intentional, reviewed, and justified

Rationale:

  - Contracts define architecture, not behavior after the fact
  - Reversing precedence (code over contract) invalidates the system

-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: No unverified assertions about repository state
-------------------------------------------------------------------------------

Agents MUST NOT make claims about repository contents, references, or wiring
without explicit verification against the repository state.

Rules:

  - Any claim that a file is unused, unreferenced, non-canonical, or safe to
    delete MUST be supported by explicit evidence from the repository
    (e.g. grep results, Makefile references, script references).
  - If verification has not been performed, the agent MUST state that it has
    not been verified and MUST request the minimal evidence needed.
  - Recommendations that depend on repository structure MUST be treated as
    invalid unless grounded in verified repository facts.

Rationale:

  - Prevents authority drift via confident but unverified assertions.
  - Forces mechanical grounding before architectural recommendations.
  - Eliminates “trust me” behavior in contract-governed systems.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Agent behavior & contract amendment boundaries
-------------------------------------------------------------------------------

Agents are advisory only.

Rules:

  - Agents MAY:
      - quote existing contract text verbatim
      - explain contract meaning
      - propose implementation changes that comply with current contracts

  - Agents MUST NOT:
      - propose amendments to this contract document
      - propose new CONTRACT blocks
      - propose edits to existing CONTRACT blocks
      - propose reformatting, reflow, or restructuring of contract text
    unless explicitly instructed by the repository owner to do so.

  - If an agent is not explicitly authorized to propose a contract change,
    the agent MUST treat the current contract text as immutable.

  - Any agent suggestion that violates document structure & formatting
    is invalid by definition and MUST be rejected.

Rationale:

  - Prevents accidental authority drift via "helpful" contract edits.
  - Forces explicit owner intent before any contract evolution.
  - Preserves documentation-as-law discipline under agent interaction.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Authority & decision ownership
-------------------------------------------------------------------------------

This system is intentionally single-authority.

Roles:

  - The operator executes, maintains, and deploys the system.
  - The repository owner is the ultimate authority over architectural intent.

Rules:

  - All architectural decisions are defined exclusively by the repository owner
    via explicit contract amendments.
  - No implementation, automation, or operational process may reinterpret,
    override, or evolve intent without an explicit contract change committed
    by the repository owner.
  - Operator actions MUST comply with the current contracts as written.
  - Disagreement between operator behavior and contract text MUST be resolved
    in favor of the contract.
  - Repository owner authority is enforced via repository access controls
    (e.g. protected branches, required approvals), not by commit authorship alone.
  - Deferring or omitting a repository-owner-mandated intent dimension
    constitutes a contract violation, regardless of implementation convenience.


Governance:

  - Authority is exercised through Git history.
  - The repository owner’s commits define intent.
  - There is no autonomous or emergent decision-making in the system.

Rationale:

  - Prevents authority drift over time.
  - Ensures all evolution is intentional, reviewable, and auditable.
  - Makes ownership explicit rather than implicit.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Repository authority & source of truth
-------------------------------------------------------------------------------

The GitHub repository at:

    https://github.com/julienbardi/homelab

is the authoritative source of truth for this system.

Rules:

  - All architectural intent, contracts, and authoritative artifacts
    MUST be derived from the GitHub repository.
  - NAS working copies, local clones, mirrors, and execution environments
    are subordinate and MUST NOT be treated as authoritative.
  - Any history rewrite, authority change, or mirroring policy change
    requires an explicit amendment to this contract and a committed change
    to the authoritative repository.
  - Implicit authority, convenience-based decisions, or agent interpretation
    of authority are forbidden.

Rationale:

  - Prevents authority drift.
  - Makes source-of-truth explicit and auditable.
  - Eliminates reliance on memory, habit, or tooling defaults.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Delegated authority
-------------------------------------------------------------------------------

The repository owner MAY designate a deputy.

Rules:

  - A deputy acts solely by explicit delegation from the repository owner.
  - Delegation MUST be documented in this contract via an explicit amendment.
  - Delegation MUST define scope and duration.
  - Delegation is revocable at any time by the repository owner.
  - A deputy MUST NOT further delegate authority.
  - In case of conflict, the repository owner’s intent always prevails.

Governance:

  - Delegation is exercised through Git history.
  - Absence of an explicit delegation implies no deputy authority.
  - There is no implicit, automatic, or time-based succession.

Rationale:

  - Enables continuity without diluting authority.
  - Prevents shared or emergent decision-making.
  - Keeps ultimate control centralized and auditable.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Temporary incapacity
-------------------------------------------------------------------------------

In the event of temporary incapacity of the repository owner,
pre-authorized delegated authority MAY become active.

Rules:

  - Temporary incapacity MUST NOT create new authority.
  - Only an explicitly designated deputy MAY act during incapacity.
  - Deputy authority during incapacity MUST be pre-authorized in advance
    by contract amendment; no new authority may be created during incapacity.
  - Scope and limits of authority during incapacity MUST be predefined.
  - Upon recovery of the repository owner, all deputy authority
    immediately reverts.

Governance:

  - There is no automatic determination of incapacity.
  - The system MUST NOT infer incapacity based on time, inactivity,
    or external signals.
  - Absence of a predefined incapacity delegation implies no authority
    during incapacity.

Rationale:

  - Preserves continuity without guessing intent.
  - Prevents emergency-driven authority drift.
  - Keeps all power transitions explicit and auditable.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Authority succession
-------------------------------------------------------------------------------

In the event of death or permanent incapacity of the repository owner,
authority MAY transfer to a designated successor.

Rules:

  - A successor MUST be explicitly designated by the repository owner
    via a contract amendment.
  - Succession MUST be documented in this contract.
  - Absence of an explicit successor designation implies no succession.
  - A successor assumes full repository owner authority upon succession.
  - Succession is a one-time transfer; further delegation follows
    standard delegation rules.
  - Succession requires the successor to possess or be granted repository
    ownership or equivalent merge authority via repository access controls.

Governance:

  - Succession is exercised through Git history.
  - There is no implicit, automatic, or external succession mechanism.

Rationale:

  - Preserves continuity without introducing ambiguity.
  - Prevents authority vacuum or contested control.
  - Keeps governance explicit, intentional, and auditable.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Scope & applicability
-------------------------------------------------------------------------------

This document defines invariants for all scripts deployed to the router.

Rules:

  - All scripts deployed to the router MUST comply with these contracts
  - Control-plane scripts are a strict subset of this scope
  - Script-specific constraints MAY be defined in additional contracts
    but MUST NOT weaken global invariants
  - Contracts apply exclusively to artifacts, scripts, and processes
    within this scope
  - External systems are out of scope unless explicitly referenced
  - No contract may be interpreted beyond its declared scope


Generalization:

  - Contracts are written to be system-agnostic where possible
  - System-specific details MUST be isolated to dedicated contracts

Any interpretation that extends a contract beyond its declared scope
is a contract violation.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Document structure & formatting
-------------------------------------------------------------------------------

This document uses a single, consistent structural grammar.

Rules:

  - Document-level boundaries MUST use '=' separators
  - Contract sections MUST use '-' separators
  - No other separator styles are permitted
  - All CONTRACT blocks MUST follow the same layout:
      separator
      CONTRACT: <name>
      separator
      body
      separator

Ordering:

  - The document header MUST appear first
  - All CONTRACT blocks MUST appear after the header
  - No content may precede the document header

Formatting is normative:

  - Visual structure is part of the contract
  - Inconsistent formatting is a contract violation
  - Cosmetic drift is forbidden
  - Line breaks inside paragraphs are semantic and intentional;
    automatic reflow or rewrapping is forbidden.
  - Whitespace and indentation inside lists are semantic and MUST be preserved.
  - Non-printable or zero-width characters are forbidden
    outside of explicitly documented encoding requirements.

Language and spelling:

  - The authoritative language of this document is English.
  - US English spelling conventions are normative.
  - Normative keywords (MUST, MUST NOT, MAY, FORBIDDEN) are interpreted
    according to their plain English meaning.
  - Spelling or grammatical errors that materially alter meaning
    constitute a contract violation.


Any change that introduces a new separator style,
alters block layout, or violates ordering rules
renders the document invalid.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Contract enforcement & failure semantics
-------------------------------------------------------------------------------

All contracts in this document are enforceable invariants.

Rules:

  - Every contract MUST be checkable by at least one script or Make target
  - Checks MUST be deterministic and side-effect free
  - Checks MUST fail loudly on violation
  - Silent degradation is forbidden

Failure semantics:

  - Any detected contract violation MUST abort execution immediately
  - Partial success is forbidden
  - Continuing after a known violation is a contract violation itself

Scope:

  - Preflight checks MUST validate all applicable contracts
  - Deployment MUST NOT proceed if any contract is violated
  - Review MUST reject changes that weaken or bypass enforcement

Contracts that cannot be enforced mechanically
are considered incomplete and invalid.

Design compliance discipline:

  - Implementations MUST satisfy contracts by design, not by exception.
  - Removing, weakening, or bypassing normative comments, assertions,
    or declarations in order to "make code work" is forbidden.
  - If a contract cannot be satisfied without altering design,
    the design MUST be revised.
  - If a contract is impractical, the contract MUST be amended explicitly
    before code changes are accepted.
  - Implementations and reviews MUST NOT rely on assumed or invented
    environment properties; all dependencies MUST be derived from
    declared contracts or verified behavior.

Rationale:

  - Contracts govern architecture, not just syntax.
  - Code that works by ignoring contract intent is invalid by definition.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Enforcement coverage declaration
-------------------------------------------------------------------------------

All contracts MUST declare their enforcement status.

Rules:

  - Every CONTRACT block MUST be classified as one of:
      - enforced
      - enforceable but not yet enforced

  - The enforcement status MUST be declared explicitly within the contract
    body using a dedicated section labeled:
        Enforcement status:

  - A contract declared as enforced MUST have at least one corresponding
    script, Make target, or validation mechanism that checks it.

  - A contract declared as enforceable but not yet enforced MUST:
      - be mechanically checkable in principle
      - NOT be treated as optional or advisory
      - be enforced before any release that claims full compliance

  - Absence of an enforcement status declaration
    constitutes a contract violation.

Rationale:

  - Makes enforcement gaps explicit and reviewable.
  - Prevents silent assumptions about coverage.
  - Preserves contract authority even before full automation exists.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Change control & evolution
-------------------------------------------------------------------------------

Contracts are stable by default.

Rules:

  - Any contract change MUST be intentional and explicit
  - Changes MUST preserve or strengthen existing invariants
  - Weakening a contract requires explicit justification

Evolution discipline:

  - New contracts MAY be added
  - Existing contracts MUST NOT be silently altered
  - Contract removal is forbidden without replacement

Review semantics:

  - Contract changes MUST be reviewed independently of code changes
  - Code that requires weakening a contract is invalid by definition

Unjustified contract drift is a contract violation.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Versioning & release semantics
-------------------------------------------------------------------------------

The control plane follows semantic versioning.

Rules:

  - All releases MUST be identified by a version of the form:
        MAJOR.MINOR.PATCH

  - While MAJOR is 0:
      - The system is considered pre-stable.
      - No backward compatibility guarantees are implied.
      - MINOR increments indicate intentional changes to contracts,
        schemas, or observable behavior.
      - PATCH increments indicate fixes or corrections that preserve
        all existing contracts and schemas.

  - A version tag MUST only be created when the system is in a known-good,
    converged state that satisfies all current contracts.

  - A release is considered eligible for tagging only if:
      - all contract enforcement checks pass
      - all validation and preflight checks pass
      - no known contract violations are deferred or ignored
      - the intent model is complete
      - the system converges without error

  - Version tags MUST NOT be created for:
      - experiments
      - partial implementations
      - known-incomplete intent models
      - states that violate or bypass any contract

  - A change that requires weakening or amending a contract
    MUST increment MINOR at minimum.

  - PATCH increments MUST NOT introduce new intent dimensions,
    schema changes, or contract amendments.

Governance:

  - Versioning semantics are defined exclusively by this contract.
  - Historical tags that predate this contract are non-authoritative
    and do not define versioning rules.
  - Future tags MUST comply with this contract.

Rationale:

  - Makes release intent explicit and reviewable.
  - Prevents version inflation and meaningless tags.
  - Aligns version numbers with architectural and contract evolution.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Runtime tool availability
-------------------------------------------------------------------------------

The router runtime environment MUST provide the following BusyBox tools:
  - awk
  - sha256sum
  - sed

Properties:

  - Tools MUST be available via BusyBox invocation
  - Vendored or standalone binaries are forbidden
  - Scripts MUST invoke tools explicitly via BusyBox
  - PATH-based resolution MUST NOT be relied upon

Rationale:

  - BusyBox is the canonical router toolchain
  - Vendoring duplicates functionality and introduces drift
  - Tool availability MUST be verifiable via direct execution

Any script or Make target that:
  - requires a vendored awk binary
  - rejects BusyBox-provided tools
  - or assumes PATH resolution

is a contract violation.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Control-plane language boundaries
-------------------------------------------------------------------------------

Python is a control-plane implementation detail.

Rules:

  - Python MAY be used for control-plane compilation, validation, and rendering
    executed off-router (e.g. WSL)
  - No script deployed to the router may require Python at runtime
  - Router-resident scripts MUST be POSIX shell compatible and rely exclusively
    on BusyBox-provided tools
  - Absence of Python on the router is expected and MUST NOT be treated as an
    error condition

Tool availability semantics:

  - BusyBox-provided tools listed in the runtime tool availability contract
    are authoritative
  - Non-availability of any required BusyBox tool is a code defect, not an
    environmental failure
  - Scripts MUST fail loudly if a required BusyBox tool is missing

Rationale:

  - The router is a constrained execution environment
  - Python is not a guaranteed runtime dependency
  - Control-plane logic must not leak into runtime execution
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Canonical storage & disaster recovery
-------------------------------------------------------------------------------

All canonical intent MUST reside on persistent router storage under /jffs/scripts/.

Canonical files:
  - domain.yaml      (domain definitions only)
  - contracts.inc    (this file)
  - Makefile         (orchestration only)

Runtime devices (router, clients) are disposable.
The entire system MUST be reconstructible from NAS backups alone.

WSL is a control-plane execution environment, NOT a source of truth.


-------------------------------------------------------------------------------
CONTRACT: Enumeration model
-------------------------------------------------------------------------------

The system enumerates the full valid state space:

    nodes × interfaces × profiles

There are:
  - no grants
  - no allow-lists
  - no selective enablement

Invalid combinations are excluded ONLY by hard constraints.

All valid combinations MUST be representable explicitly in the
authoritative compiled dump (plan.tsv).
plan.tsv is the sole source of truth for intent resolution.

-------------------------------------------------------------------------------
CONTRACT: Compiled dumps
-------------------------------------------------------------------------------

The following files are materialized database snapshots:

  - plan.tsv   (authoritative intent representation)
  - alloc.tsv
  - keys.tsv

The legacy file plan.v1.tsv is no longer emitted and MUST NOT exist

Properties:
  - Deterministic
  - Complete (no hidden runtime state)
  - Flat and relational
  - Excel-friendly
  - Never edited by hand
  - Authoritative once generated

If a configuration exists at runtime, it MUST exist in the dump.

Dump emission is OPTIONAL and controlled by:

    WG_DUMP=1

When WG_DUMP is unset or 0, dumps MUST NOT be written.


-------------------------------------------------------------------------------
CONTRACT: Interfaces
-------------------------------------------------------------------------------

The 'iface' field uniquely identifies the WireGuard server endpoint.

Additional server realization parameters (e.g. host location, MTU,
listen port) MUST be represented explicitly as first-class intent
dimensions in authoritative compiled dumps.

The 'iface' field remains the stable identity key for server endpoints.

Examples:
  - wg1..wg15  → NAS-hosted WireGuard servers
  - wgs        → Router-hosted WireGuard server

All server identity is keyed by 'iface'.

Server realization (keys, firewall rules, routing, deployment)
MUST be derived from authoritative compiled intent associated
with that iface, not from implicit conventions or naming.


-------------------------------------------------------------------------------
CONTRACT: Schema authority & consumer closure
-------------------------------------------------------------------------------

Authoritative compiled dumps define the system schema.

Rules:

  - Any change to the schema of an authoritative dump (e.g. plan.tsv)
    MUST be accompanied by full consumer closure in the same change-set.
  - Consumer closure means:
      - All renderers, checkers, and deployment scripts that read the dump
        are updated to the new schema.
      - All legacy schema assumptions are removed or explicitly version-gated.
  - Partial schema migrations are forbidden.
  - A schema change is invalid if any consumer still relies on the previous
    schema, even if runtime behavior appears correct.

Enforcement:

  - Every authoritative dump MUST declare a schema identifier and version
    in a header comment.
  - All consumers MUST validate the expected schema identifier and version
    before processing.
  - Any mismatch MUST abort execution immediately.

Rationale:

  - Prevents silent schema drift.
  - Forces architectural changes to be completed end-to-end.
  - Makes incomplete migrations mechanically impossible.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Intent dimension completeness
-------------------------------------------------------------------------------

All first-class intent dimensions MUST be represented explicitly
in authoritative compiled dumps.

Rules:

  - If a dimension affects realization (rendering, deployment, or behavior),
    it MUST appear as an explicit field in the authoritative dump.
  - Deferring representation of a required intent dimension is forbidden.
  - "We will add this later" is invalid unless the dimension is explicitly
    declared non-authoritative and non-impacting by contract amendment.

Examples of first-class dimensions include (non-exhaustive):
  - client operating system
  - server host location
  - MTU
  - routing domain

Rationale:

  - Prevents hidden or implicit intent.
  - Ensures renderers remain dumb consumers.
  - Forces completeness at design time, not after breakage.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
CONTRACT: Compile-time intent dimensions
-------------------------------------------------------------------------------

Certain intent dimensions are resolved fully during compilation and do not
remain authoritative post-compile.

Rules:

  - The following intent dimensions are compile-time only:
      - profile
      - lan_access
      - internet_v4
      - internet_v6
      - user_id

  - Compile-time intent dimensions MUST NOT appear as fields in authoritative
    compiled dumps (e.g. plan.tsv).

  - The effects of compile-time intent dimensions MUST be fully materialized
    into authoritative compiled facts prior to dump emission.

  - No renderer, checker, or deployment script may rely on the presence,
    absence, or value of any compile-time intent dimension.

  - Any runtime behavior attributable to a compile-time intent dimension
    MUST be derivable solely from authoritative compiled facts.

Clarifications:

  - Compile-time intent dimensions may influence compilation logic but
    MUST NOT survive as labels, flags, or policy indicators post-compile.

  - Retaining compile-time intent dimensions in authoritative dumps is
    forbidden, as it introduces redundant authority and enables implicit
    inference.

Rationale:

  - Preserves single-source authority in compiled dumps.
  - Prevents policy labels from leaking into runtime artifacts.
  - Ensures renderers remain dumb consumers of fully resolved intent.
  - Eliminates ambiguity between intent labels and realized behavior.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Intent inventory
-------------------------------------------------------------------------------

The system MUST maintain an explicit inventory of intent dimensions.

Rules:

  - All first-class intent dimensions MUST be listed explicitly
    in a dedicated, versioned section of the contract or a referenced
    intent inventory document.
  - Adding a new intent dimension requires:
      - updating the inventory
      - updating authoritative dumps
      - updating all consumers
    in the same change-set.

  - An intent dimension not listed in the inventory MUST NOT be used
    by any implementation.

Rationale:

  - Makes intent scope explicit and reviewable.
  - Prevents late discovery of missing dimensions.
  - Forces architectural thinking before coding.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Design completeness gate
-------------------------------------------------------------------------------

Implementation MUST NOT proceed until the intent model is complete.

Rules:

  - All first-class intent dimensions MUST be:
      - identified
      - named
      - placed in authoritative compiled dumps
      - and validated
    before any renderer or deployment logic is written or modified.

  - Introducing or modifying implementation code while the intent model
    is incomplete is forbidden.

  - "Temporary" or "placeholder" implementations are forbidden
    for unresolved intent dimensions.

Enforcement:

  - A design is considered incomplete if any required intent dimension
    is known but not yet represented in authoritative dumps.
  - Any attempt to render, deploy, or apply with an incomplete intent
    model MUST abort execution.

Rationale:

  - Prevents implementation from driving architecture.
  - Forces intent modeling to finish before code exists.
  - Eliminates drift caused by incremental guessing.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Broken model freeze
-------------------------------------------------------------------------------

If the intent model is known to be incomplete or inconsistent,
no further implementation work is permitted.

Rules:

  - While the intent model is incomplete, the only permitted changes are:
      - contract amendments
      - intent model completion
      - validation logic

  - Adding or modifying renderers, deployment logic, or orchestration
    while the model is incomplete is forbidden.

Rationale:

  - Prevents compounding errors.
  - Forces resolution at the correct layer.
  - Makes architectural failure a hard stop, not a detour.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: TSV encoding
-------------------------------------------------------------------------------

All dump files are UTF-8 encoded TSV with:

  - ASCII TAB (0x09) as field delimiter
  - LF (0x0A) as line terminator
  - No quoting
  - No escaping

Forbidden inside any field:

  - ASCII NUL (0x00)
  - TAB (0x09)
  - LF (0x0A)
  - CR (0x0D)

Quotes (", ') have NO special meaning.

Any violation MUST abort compilation loudly.


-------------------------------------------------------------------------------
CONTRACT: TSV schema literals in code
-------------------------------------------------------------------------------

TSV schemas referenced in source code MUST be represented using explicit
escape sequences.

Rules:

  - Source code MUST NOT contain literal ASCII TAB characters (0x09)
    when expressing TSV headers, schemas, or field lists.
  - All TSV schema literals in code MUST use the '\t' escape sequence
    to represent field delimiters.
  - Literal TAB characters are permitted ONLY in runtime data files
    (e.g. *.tsv dumps), not in source code.
  - Implementations MUST compare normalized header strings against
    escaped schema literals, not raw tab characters.

Examples:

  Correct:
    "user_id\tdisplay_name\temail\tenabled"

  Forbidden:
    "user_id    display_name    email   enabled"

Rationale:

  - Literal tabs are invisible, editor-dependent, and prone to silent corruption.
  - Escaped delimiters make schemas explicit, reviewable, and copy-safe.
  - Prevents false negatives caused by editor, formatter, or transport behavior.
  - Preserves strict TSV semantics without weakening validation.

Any source file containing a literal TAB character in a TSV schema
representation is a contract violation.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Deterministic ordering
-------------------------------------------------------------------------------

All dump rows MUST be emitted in a stable, deterministic order.

Sorting keys MUST be explicit and consistent across runs.

This guarantees:
  - clean diffs
  - reliable drift detection
  - trustworthy Excel inspection


-------------------------------------------------------------------------------
CONTRACT: Profiles
-------------------------------------------------------------------------------

Profiles are named routing intents.

Properties:
  - Textual identifiers with documented meaning
  - Not OS-specific
  - Not user-specific
  - Not grants
  - Not selections

Profiles describe intent ONLY.
Realization happens at render time.


-------------------------------------------------------------------------------
CONTRACT: Key lifecycle
-------------------------------------------------------------------------------

Client keys are scoped to:

    (base, iface)

Keys are:
  - generated idempotently
  - never rotated implicitly

Profile or OS changes MUST NOT affect key identity.


-------------------------------------------------------------------------------
CONTRACT: Renderers
-------------------------------------------------------------------------------

Renderers are dumb consumers of the authoritative compiled plan (plan.tsv).

Renderers MUST perform:
  - no address math
  - no policy inference
  - no intent resolution

All intent MUST be resolved at compile time.

Additional rules:
  - Renderers MUST NOT assume default values for missing intent.
  - Renderers MUST NOT derive intent from naming conventions,
    numeric suffixes, or historical behavior.
  - If required intent is missing from the compiled dump,
    rendering MUST fail loudly.
  - Renderers MUST NOT tolerate unused or ignored fields
    in authoritative dumps.

Rationale:
  - Prevents reintroduction of implicit behavior.
  - Ensures all intent is resolved at compile time.


-------------------------------------------------------------------------------
CONTRACT: Wiring order
-------------------------------------------------------------------------------

WireGuard is the foundational layer.

Dependency order:

  1. WireGuard (identity, routing domains, interfaces)
  2. Firewall / NAT (keyed on WG interfaces)
  3. Higher-level services (e.g. Caddy)

No service above WireGuard may influence WireGuard intent.


-------------------------------------------------------------------------------
CONTRACT: Make orchestration & deployment
-------------------------------------------------------------------------------

Make executes locally (WSL). The router is the canonical runtime store.

Deployment model:
  - Each deployed router artifact MUST have exactly one owning Make target.
  - No two targets may write the same destination path on the router.
  - No overlapping recipes are permitted (single-writer per artifact).

Execution integrity:
  - Any Make target that executes artifacts on the router MUST depend on
    the Make target that installs or updates those artifacts.
  - Executing router-resident scripts without an explicit installation
    dependency is forbidden.
  - Running stale artifacts is a contract violation, regardless of
    apparent runtime success.

Installation semantics:
  - Make MUST NOT use install(1) for router deployment.
  - Deployment MUST be explicit and auditable (scp/ssh or equivalent).
  - Deployment MUST be atomic on the router:
      write to a temporary path, then mv -f into place.

Graph discipline:
  - graph.mk defines dependency order only.
  - Module .mk files may define recipes, but only for artifacts they own.
  - config.mk defines variables only; no targets, no recipes, no side effects.

Concurrency semantics:

  - .NOTPARALLEL is file-local and does NOT propagate across included Makefiles.
  - Any target listed in a .NOTPARALLEL declaration MUST be declared in the same file.
  - Centralizing .NOTPARALLEL in an including file is forbidden.

Structural enforcement:
  - When a Makefile is split, all concurrency constraints MUST be re-established
    in the owning module files.
  - Failure to re-declare required .NOTPARALLEL constraints after a split
    is a contract violation, even if behavior appears unchanged under -j1.

Recursive invocation discipline:

  - Makefile recipes MUST NOT invoke $(MAKE) or make recursively.
  - All dependency relationships MUST be expressed in the static Make graph.
  - Control flow via recursive Make invocation is forbidden.
  - Capability checks and preflight validation MUST be modeled as explicit
    dependencies or standalone verification targets, not invoked imperatively.

Rationale:

  - Recursive Make bypasses dependency visibility.
  - It breaks determinism and auditability.
  - It introduces hidden execution order and side effects.
  - It defeats Make’s core purpose as a declarative build graph.

Any Makefile that invokes $(MAKE) inside a recipe is invalid.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Makefile shell constructs
-------------------------------------------------------------------------------

Makefile recipes MUST NOT use shell here-documents (<<EOF or variants).

Rules:

  - Here-documents are forbidden in all Makefile recipes
  - Multi-line shell logic MUST be expressed using:
      - single-line commands
      - explicit shell scripts
      - or external script files
  - Makefile recipes MUST remain line-oriented and tab-prefixed

Rationale:

  - GNU Make does not parse here-documents reliably
  - Here-documents introduce non-local syntax errors
  - Failures manifest as misleading "missing separator" errors
  - Debugging becomes non-deterministic and error-prone

Enforcement:

  - Any Makefile containing a here-document is invalid
  - Review MUST reject such changes
  - Refactoring to external scripts is mandatory

This is a structural invariant, not a stylistic preference.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: File size & structural limits
-------------------------------------------------------------------------------

No Makefile may exceed 10000 characters.

Rationale:
  - Files beyond this size become non-local to review
  - Ownership boundaries blur
  - Accidental coupling and overlap become likely

Enforcement:
  - If a Makefile exceeds this limit, responsibilities MUST be split
    along existing ownership boundaries.
  - Splitting MUST NOT introduce new behavior, targets, or semantics.
  - The resulting files MUST preserve identical dependency graphs
    and execution behavior.

This is a structural invariant, not a stylistic guideline.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Documentation correctness
-------------------------------------------------------------------------------

All comments that describe structure, ordering, ownership, or intent
are normative and MUST be correct.

This applies to:
  - File headers
  - Section headers
  - Module inclusion order descriptions
  - Target ownership descriptions
  - Any comment that explains "what this is" or "how this is wired"

In particular:
  - Any comment describing inclusion order MUST exactly match the
    actual include order in the file.
  - Any comment describing ownership or responsibility MUST match
    the actual owning target or module.
  - Any comment describing behavior or semantics MUST reflect
    current reality, not historical intent.

Comments are documentation-as-law:
  - A misleading comment is a contract violation.
  - A stale comment is a bug.
  - Updating code without updating its descriptive comments
    is forbidden.

If code and comments disagree, the system is considered invalid
until corrected.

Enforcement:
  - Any change that alters structure, ordering, ownership, or behavior
    MUST update the corresponding descriptive comments in the same change.
  - Review MUST reject changes where comments and code diverge,
    even if runtime behavior is otherwise correct.

-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Content addressing & hashing
-------------------------------------------------------------------------------

Deployment and drift detection rely on SHA-256 content hashing.

The router platform MUST provide SHA-256 hashing via one of:
  - sha256sum(1)
  - busybox sha256sum

Implementations MUST accept either form.

Requiring a standalone sha256sum binary is forbidden.

Any deployment logic that rejects BusyBox sha256sum
is a contract violation.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
CONTRACT: Non-goals
-------------------------------------------------------------------------------

This document intentionally does NOT define:

  - Performance targets
  - Feature roadmaps
  - User experience guarantees
  - Operational SLAs
  - Organizational policy

Rationale:

  - Contracts define invariants, not aspirations
  - Mixing goals with invariants weakens both
  - Non-goals are explicit to prevent scope creep

Any attempt to encode goals, preferences, or aspirations
as contracts is a contract violation.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
CONTRACT: Execution root & working directory confinement
-------------------------------------------------------------------------------

All control-plane scripts MUST execute with a well-defined execution root.

Rules:

  - Every script deployed to the router MUST explicitly set its working
    directory at startup.
  - The working directory MUST be the directory containing the script itself.
  - Relative paths MUST be resolved exclusively within this directory tree.
  - Reliance on caller-provided working directories is forbidden.

Enforcement:

  - Scripts MUST perform an explicit directory change at startup.
  - Failure to establish the execution root MUST abort execution immediately.

Rationale:

  - Prevents accidental writes to arbitrary filesystem locations
  - Ensures deterministic artifact placement
  - Eliminates execution-context ambiguity
  - Makes side effects auditable and inspectable

Any script that emits files relative to an implicit or inherited working
directory is a contract violation.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
CONTRACT: Write confinement & side-effect boundaries
-------------------------------------------------------------------------------

Control-plane scripts MUST NOT write outside their declared ownership scope.

Rules:

  - Each script MUST have a single, declared output directory.
  - All file creation, modification, or deletion MUST occur within this scope.
  - Writing to parent directories or unrelated paths is forbidden.
  - Temporary files MUST be created within the same confined scope.

Confidentiality:

  - Materialized intent, keys, or derived artifacts MUST NOT be written
    to shared, global, or user home directories.
  - Leakage of control-plane artifacts outside the confined scope
    is a critical contract violation.

Enforcement:

  - Scripts MUST fail if an output path resolves outside the allowed scope.
  - Silent redirection or fallback paths are forbidden.

Rationale:

  - Prevents accidental disclosure of sensitive material
  - Enables reliable cleanup and disaster recovery
  - Makes filesystem effects predictable and reviewable
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Dump locality & inspectability
-------------------------------------------------------------------------------

All compiled dumps MUST be emitted into a canonical, inspectable location.

Rules:

  - plan.tsv, alloc.tsv, and keys.tsv MUST be written to the same directory
    as the compiler scripts.
  - Dump locations MUST NOT depend on invocation context.
  - Dump emission MUST be atomic and overwrite previous dumps.

Observability:

  - Dump files MUST be discoverable without prior knowledge of execution context.
  - Inspecting dumps MUST NOT require guessing or searching the filesystem.

Rationale:

  - Dumps are authoritative database snapshots
  - Their location is part of the contract
  - Inspectability is a correctness requirement, not a convenience
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Connectivity preservation & management access
-------------------------------------------------------------------------------

Loss of LAN connectivity or management access is the highest-severity failure.

Rules:

  - Firewall changes MUST preserve uninterrupted LAN connectivity at all times
  - Router management access (SSH, HTTPS) MUST remain reachable from the LAN
  - Intranet access for LAN users MUST NOT be disrupted by firewall changes
  - Internet access for LAN users MUST NOT be interrupted by control-plane
    deployment or firewall mutation

Protected services (non-exhaustive):

  - SSH access to the router (TCP/22 or configured alternative)
  - HTTPS access to the router and NAS (TCP/443)
  - Administrative access ports explicitly declared as critical (e.g. TCP/2222)

Failure semantics:

  - Any change that risks loss of connectivity is forbidden
  - Any firewall logic that could transiently drop management access
    is a contract violation
  - Safety of existing connectivity takes precedence over architectural
    cleanliness, refactoring, or optimization

Enforcement:

  - Firewall implementations MUST explicitly preserve critical allow rules
  - Review MUST reject any change that removes or weakens connectivity guarantees
  - Connectivity preservation MUST be validated before deployment

Rationale:

  - The router is a family-critical infrastructure component
  - Loss of connectivity has immediate real-world impact
  - Recoverability is irrelevant if access is lost
  - Safety dominates elegance

-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Router mutation exclusivity
-------------------------------------------------------------------------------

All mutation of router runtime state (firewall, routing, interfaces, services)
MUST occur exclusively inside router-resident scripts deployed under
/jffs/scripts/.

Rules:

  - Makefile recipes MUST NOT invoke iptables, ip6tables, nft, sysctl,
    or any other router-mutating command directly.
  - Makefile recipes MUST NOT stream commands over SSH for execution.
  - Router state MUST NOT be mutated via ad-hoc SSH command execution.
  - All router mutations MUST be performed by a deployed script that:
      - resides under /jffs/scripts/
      - is owned by exactly one Make target
      - is deployed atomically
      - is executable independently of the control plane

Rationale:

  - Prevents partial execution and mid-flight failure
  - Preserves atomicity and rollback guarantees
  - Enforces single-writer ownership
  - Keeps control-plane logic off the router
  - Makes runtime behavior auditable and reconstructible

Any Makefile that mutates router state without deploying and invoking
a router-resident script is invalid.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: License & reuse
-------------------------------------------------------------------------------

This contract text is licensed for use, reuse, and adaptation under the
following conditions:

  - Attribution to the original author is required
  - Modifications MUST be clearly documented
  - Derived contracts MUST preserve or strengthen invariants
  - Misrepresentation of modified contracts as original is forbidden

This license applies to the contract text itself,
independent of any code governed by it.

Use of this contract implies acceptance of its terms.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Interface lifecycle & revocation
-------------------------------------------------------------------------------

Each WireGuard interface has an explicit lifecycle state.

States:
  - active       → fully supported and rendered
  - deprecated   → still rendered, scheduled for removal
  - revoked      → MUST NOT be rendered or deployed

Rules:

  - Every interface MUST declare exactly one lifecycle state
  - Revoked interfaces MUST NOT appear in any compiled dump
  - Deprecated interfaces MAY be rendered but MUST emit a warning
  - Lifecycle transitions MUST be explicit and version-controlled

Grace periods:

  - Deprecation MAY include a documented revocation date
  - Enforcement of revocation dates MUST be deterministic

Rationale:

  - Prevents silent zombie interfaces
  - Enables controlled peer migration
  - Makes interface retirement auditable and predictable
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Interface host binding
-------------------------------------------------------------------------------

WireGuard interfaces are host-bound and immutable.

Rules:

  - Each interface is bound to exactly one host
  - Host binding MUST NOT change over the lifetime of an interface
  - Changing host requires interface replacement
  - Interface replacement implies new server key material

Migration semantics:

  - Live migration of an interface between hosts is forbidden
  - Replacement MUST be explicit and disruptive by design

Rationale:

  - Host identity defines trust, routing, and firewall authority
  - Migration would introduce ambiguous state and hidden coupling
  - Replacement preserves auditability and correctness
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: NAT66 capability constraints
-------------------------------------------------------------------------------

NAT66 is an explicit, opt-in capability.

Rules:

  - NAT66 MUST NOT be enabled implicitly
  - NAT66 MAY be enabled on any host only if explicitly requested
  - NAT66 requests MUST fail if IPv6 egress is unavailable
  - Renderers MUST NOT infer or synthesize NAT66 behavior

Host semantics:

  - Router-hosted NAT66 is expected and supported
  - NAS-hosted NAT66 is permitted but MUST be explicit

Rationale:

  - Prevents accidental IPv6 policy changes
  - Preserves safety while allowing controlled experimentation
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Routing authority
-------------------------------------------------------------------------------

Routing authority is centralized on the router.

Rules:

  - Routing intent MAY originate from any host
  - Only the router may install or modify routing state
  - Router MAY refuse routing intent that violates firewall or
    connectivity preservation contracts

Rationale:

  - Preserves a single source of routing truth
  - Prevents split-brain routing behavior
  - Aligns with Step 6 firewall invariants
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Host identity
-------------------------------------------------------------------------------

The WireGuard control plane recognizes exactly two hosts:

  - router
  - nas

Rules:

  - All interfaces MUST be bound to one of these hosts
  - Introducing additional hosts requires an explicit contract amendment
  - Host identity is semantic, not address-based

Rationale:

  - Prevents accidental expansion of the trust and routing domain
  - Makes host authority explicit and reviewable
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Broken model freeze
-------------------------------------------------------------------------------

If the intent model is known to be incomplete or inconsistent,
no further implementation work is permitted.

Rules:

  - The only allowed changes while the model is broken are:
      - contract amendments
      - intent model completion
      - validation logic

  - Adding features, refactoring, or deployment logic
    while the model is broken is forbidden.

Rationale:

  - Prevents compounding errors.
  - Forces resolution at the correct layer.
-------------------------------------------------------------------------------


===============================================================================
End of contracts.inc
===============================================================================
